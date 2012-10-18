package Module::AnyEvent::Helper;

use strict;
use warnings;

use Carp;

# VERSION
require Exporter;
our (@ISA) = qw(Exporter);
our (@EXPORT_OK) = qw(strip_async strip_async_all bind_scalar bind_array);

sub _strip_async
{
	my ($pkg, @func) = @_;
	foreach my $func (@func) {
		croak "$func does not end with _async" unless $func =~ /_async$/;
		my $new_func = $func;
		$new_func =~ s/_async$//;

		no strict 'refs'; ## no critic (ProhibitNoStrict)
		*{$pkg.'::'.$new_func} = sub {
			shift->$func(@_)->recv;
		};
	}
}

sub strip_async
{
	my $pkg = caller;
	_strip_async($pkg, @_);
}

sub strip_async_all
{
	my $pkg = caller;
	no strict 'refs'; ## no critic (ProhibitNoStrict)
	_strip_async($pkg, grep { /_async$/ && defined *{$pkg.'::'.$_}{CODE} } keys %{$pkg.'::'});
}

my $guard = {};

sub bind_scalar
{
	my ($gcv, $lcv, $succ) = @_;

	$lcv->cb(sub {
		my $ret = $succ->(shift);
		$gcv->send($ret) if $ret != $guard;
	});
	$guard;
}

sub bind_array
{
	my ($gcv, $lcv, $succ) = @_;

	$lcv->cb(sub {
		my @ret = $succ->(shift);
		$gcv->send(@ret) if @ret != 1 || $ret[0] != $guard;
	});
	$guard;
}

1;
__END__
=head1 NAME

Module::AnyEvent::Helper - Helper module to make other modules AnyEvent-friendly

=head1 SYNOPSIS

By using this module, ordinary (synchronous) method:

  sub func {
    my $ret1 = func2();
    # ...1
  
    my $ret2 = func2();
    # ...2
  }

can be mechanically translated into AnyEvent-friendly method as func_async:

  use Module::AnyEvent::Helper qw(bind_scalar strip_async_all)

  sub func_async {
    my $cv = AE::cv;
  
    bind_scalar($cv, func2_async(), sub {
      my $ret1 = shift->recv;
      # ...1
      bind_scalar($cv, func2_async(), sub {
        my $ret2 = shift->recv;
        # ...2
      });
    });

    return $cv;
  }

At the module end, calling strip_async_all makes synchronous versions of _async methods in the calling package.

  strip_async_all;

=head1 DESCRIPTION

AnyEvent-friendly versions of modules already exists for many modules.
Most of them are intended to be drop-in-replacement of original module.
In this case, return value should be the same as original.
Therefore, at the last of the method in the module, blocking wait is made usually.

  sub func {
    # some asynchronous works
    $cv->recv; # blocking wait
    return $ret;
  }

However, this blocking wait almost prohibit to use the module with plain AnyEvent, because of recursive blocking wait error.
Using Coro is one solution, and to make a variant of method to return condition variable is another.
To employ the latter solution, semi-mechanical works are required.
This module reduces the work bit.

=head1 CLASS METHODS

All class methods can be exported but none is exported in default.

=over 4

=item strip_async(I<method_names>...)

Make synchronous version for each specified method
All method names MUST end with _async.
If 'func_async' is passed, the following 'func' is made into the calling package.

  sub func { shift->func_async(@_)->recv; }

Therefore, func_async MUST be callable as method.

=item strip_async_all()

strip_async is called for all methods end with _async in the calling package.
NOTE that error occurs if function, that is not a method, having _async suffix exists.

=item bind_scalar(I<cv1>, I<cv2>, I<successor>)

I<cv1> and I<cv2> MUST be AnyEvent condition variables. I<successor> MUST be code reference.

You can consider I<cv2> is passed to I<successor>, then return value of I<successor>, forced in scalar-context, is sent by I<cv1>.
Actually, there is some treatment for nested call of bind_scalar/bind_array.

=item bind_array(I<cv1>, I<cv2>, I<successor>)

Similar as bind_scalar, but return value of successor is forced in array-context.

=back

=head1 AUTHOR

Yasutaka ATARASHI C<yakex@cpan.org>

=head1 LICENSE

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut
