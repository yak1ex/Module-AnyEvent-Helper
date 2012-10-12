use strict;
use warnings;

use Test::More tests => 2;
use AnyEvent;

package target;

use Module::AnyEvent::Helper qw(bind_array bind_scalar strip_async_all);

sub new { return bless {}; }

sub func1_async
{
	my $cv = AE::cv;
	my $w; $w = AE::timer 2, 0, sub { undef $w; $cv->send(1); };
	return $cv;
}

sub func2_async
{
	my $cv = AE::cv;
	my $w; $w = AE::timer 2, 0, sub { undef $w; $cv->send(1,2); };
	return $cv;
}

sub func3_async
{
	my $cv = AE::cv;
	my ($self, $arg) = @_;
	bind_scalar($cv, func1_async(), sub {
		return shift->recv if $arg == 1;
		bind_array($cv, func2_async(), sub {
			return shift->recv if $arg == 2;
		});
	});
	return $cv;
}


strip_async_all;

package main;

my $obj = target->new;
ok($obj->func3(1) == 1);
is_deeply([$obj->func3(2)], [1,2]);
