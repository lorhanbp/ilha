use strict;
use warnings;
use DynaLoader;
$| = 1;
my ($library, $mode) = @ARGV;
my $handle = DynaLoader::dl_load_file($library, 0) or die "ilha: " . DynaLoader::dl_error() . "\n";
my $symbol = DynaLoader::dl_find_symbol($handle, "ilha_$mode") or die "ilha: modo desconhecido\n";
DynaLoader::dl_install_xsub("main::ilha_run", $symbol);
ilha_run();
