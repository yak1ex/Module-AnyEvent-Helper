use Test::More tests => 3;

BEGIN { use_ok('Module::AnyEvent::Helper::PPI::Transform'); }

my $target = <<'EOF';
package Test;

use strict;
use warnings;

sub new
{
	return bless {};
}

sub func1
{
	return 1;
}

my $ref = { func1 => 1, 1 + func1 => 2 };

sub func2
{
	return 2;
}

sub func3
{
	my ($self, $arg) = @_;
	return func1() if $arg == $ref->{func1};
	return func2() if $arg == 2;
	return func4();
}
1;
EOF

my $result = <<'EOF';
use AnyEvent;use Module::AnyEvent::Helper;package Test;

use strict;
use warnings;





my $ref = { func1 => 1, 1 + func1 => 2 };



sub func3_async
{my $___cv___ = AE::cv;
	my ($self, $arg) = @_;
	Module::AnyEvent::Helper::bind_scalar($___cv___, func1_async(), sub {
return shift->recv() if $arg == $ref->{func1};
	Module::AnyEvent::Helper::bind_scalar($___cv___, func2_async(), sub {
return shift->recv() if $arg == 2;
	Module::AnyEvent::Helper::bind_scalar($___cv___, func4_async(), sub {
return shift->recv();
});});});return $___cv___;}
1;Module::AnyEvent::Helper::strip_async_all();1;
EOF

my $trans = Module::AnyEvent::Helper::PPI::Transform->new(
	-remove_func => [qw(func1 func2)],
	-translate_func => [qw(func3)],
	-replace_func => [qw(func4)],
	-delete_func => [qw(new)],
);
ok($trans->apply(\$target));
# TODO: Maybe it is adequate to check significant elements only
is($target, $result);
