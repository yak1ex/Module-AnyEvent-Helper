package Module::AnyEvent::Helper;

use strict;
use warnings;

# VERSION
require Exporter;
our (@ISA) = qw(Exporter);
our (@EXPORT_OK) = qw(strip_async strip_async_all);

sub strip_async
{
	my (@func) = @_;
	my $pkg = caller;
	foreach my $func (@func) {
		die unless $func =~ /_async$/;
		my $new_func = $func;
		$new_func =~ s/_async$//;

		no strict 'refs';
		*{$pkg.'::'.$new_func} = sub {
			shift->$func(@_)->recv;
		};
	}
}

sub strip_async_all
{
	my $pkg = caller;
	no strict 'refs';
	strip_async(grep { defined *{$pkg.'::'.$_}{CODE} } keys %{$pkg.'::'});
}

1;
