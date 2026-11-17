#import <Foundation/Foundation.h>
#import <dlfcn.h>
typedef void (*InfoFn)(dispatch_queue_t, void (^)(NSDictionary *));
typedef void (*PlayFn)(dispatch_queue_t, void (^)(BOOL));
typedef BOOL (*CmdFn)(uint32_t, NSDictionary *);

static void *mr(void) {
    return dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW);
}

static NSString *lastKey = nil;
static BOOL artSent = NO;
static BOOL watching = NO;

static void emit(BOOL withArt) {
    void *h = mr();
    InfoFn getInfo = h ? (InfoFn)dlsym(h, "MRMediaRemoteGetNowPlayingInfo") : NULL;
    PlayFn getPlaying = h ? (PlayFn)dlsym(h, "MRMediaRemoteGetNowPlayingApplicationIsPlaying") : NULL;
    if (!getInfo) { puts("{}"); return; }
    __block BOOL playing = NO;
    __block NSDictionary *info = nil;
    dispatch_semaphore_t a = dispatch_semaphore_create(0), b = dispatch_semaphore_create(0);
    if (getPlaying) getPlaying(dispatch_get_global_queue(0, 0), ^(BOOL p) { playing = p; dispatch_semaphore_signal(a); });
    else dispatch_semaphore_signal(a);
    getInfo(dispatch_get_global_queue(0, 0), ^(NSDictionary *i) { info = i; dispatch_semaphore_signal(b); });
    dispatch_semaphore_wait(a, dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC));
    dispatch_semaphore_wait(b, dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC));
    NSMutableDictionary *o = [NSMutableDictionary dictionary];
    for (NSString *k in @[@"Title", @"Artist", @"Album", @"Duration", @"ElapsedTime"]) {
        id v = info[[@"kMRMediaRemoteNowPlayingInfo" stringByAppendingString:k]];
        if (v) o[[k lowercaseString]] = v;
    }
    NSDate *stamp = info[@"kMRMediaRemoteNowPlayingInfoTimestamp"];
    if ([stamp isKindOfClass:[NSDate class]]) o[@"timestamp"] = @(stamp.timeIntervalSince1970);
    id rate = info[@"kMRMediaRemoteNowPlayingInfoPlaybackRate"];
    if (rate) o[@"rate"] = rate;
    if (watching) {
        NSString *key = [NSString stringWithFormat:@"%@|%@", o[@"title"] ?: @"", o[@"artist"] ?: @""];
        if (![key isEqualToString:lastKey]) { lastKey = key; artSent = NO; }
        withArt = !artSent;
    }
    if (withArt) {
        NSData *art = info[@"kMRMediaRemoteNowPlayingInfoArtworkData"];
        if ([art isKindOfClass:[NSData class]]) { o[@"artwork"] = [art base64EncodedStringWithOptions:0]; artSent = YES; }
    }
    o[@"playing"] = @(playing);
    NSData *d = [NSJSONSerialization dataWithJSONObject:o options:0 error:nil];
    fwrite(d.bytes, 1, d.length, stdout);
    fputc('\n', stdout);
    fflush(stdout);
}

static void command(uint32_t c) {
    void *h = mr();
    CmdFn send = h ? (CmdFn)dlsym(h, "MRMediaRemoteSendCommand") : NULL;
    if (send) send(c, nil);
}

void ilha_get(void *cv) { emit(NO); }
void ilha_getart(void *cv) { emit(YES); }
void ilha_toggle(void *cv) { command(2); }
void ilha_next(void *cv) { command(4); }
void ilha_prev(void *cv) { command(5); }

void ilha_watch(void *cv) {
    void *h = mr();
    typedef void (*RegFn)(dispatch_queue_t);
    RegFn reg = h ? (RegFn)dlsym(h, "MRMediaRemoteRegisterForNowPlayingNotifications") : NULL;
    if (reg) reg(dispatch_get_main_queue());
    watching = YES;
    dispatch_queue_t q = dispatch_queue_create("ilha.emit", DISPATCH_QUEUE_SERIAL);
    void (^fire)(NSNotification *) = ^(NSNotification *n) { dispatch_async(q, ^{ emit(NO); }); };
    for (NSString *name in @[@"kMRMediaRemoteNowPlayingInfoDidChangeNotification",
                             @"kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification",
                             @"kMRMediaRemoteNowPlayingApplicationDidChangeNotification"]) {
        [[NSNotificationCenter defaultCenter] addObserverForName:name object:nil queue:nil usingBlock:fire];
    }
    [NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(NSTimer *t) { dispatch_async(q, ^{ emit(NO); }); }];
    dispatch_async(q, ^{ emit(NO); });
    CFRunLoopRun();
}
