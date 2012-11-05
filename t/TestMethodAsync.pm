package TestMethodAsync;

sub func1_async()
{
	my $cv = AE::cv;
	my $w; $w = AE::timer 2, 0, sub { undef $w; $cv->send(1); };
	return $cv;
}

sub func2_async()
{
	my $cv = AE::cv;
	my $w; $w = AE::timer 2, 0, sub { undef $w; $cv->send(2); };
	return $cv;
}

use Module::AnyEvent::Helper::Filter -as => TestMethodAsync, -target => TestMethod,
	-remove_func => [qw(func1 func2)], -translate_func => [qw(func3)];

1;
