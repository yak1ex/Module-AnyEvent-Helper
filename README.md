# NAME

Module::AnyEvent::Helper - Helper module to make other modules AnyEvent-friendly

# VERSION

version v0.0.3

# SYNOPSIS

By using this module, ordinary (synchronous) method:

    sub func {
      my $ret1 = func2();
      # ...1
    

      my $ret2 = func2();
      # ...2
    }

can be mechanically translated into AnyEvent-friendly method as func\_async:

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

At the module end, calling strip\_async\_all makes synchronous versions of \_async methods in the calling package.

    strip_async_all;

# DESCRIPTION

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

# FUNCTIONS

All functions can be exported but none is exported in default.

## strip\_async(_method\_names_...)

Make synchronous version for each specified method
All method names MUST end with \_async.
If 'func\_async' is passed, the following 'func' is made into the calling package.

    sub func { shift->func_async(@_)->recv; }

Therefore, func\_async MUST be callable as method.

## strip\_async\_all()

strip\_async is called for all methods end with \_async in the calling package.
NOTE that error occurs if function, that is not a method, having \_async suffix exists.

## bind\_scalar(_cv1_, _cv2_, _successor_)

_cv1_ and _cv2_ MUST be AnyEvent condition variables. _successor_ MUST be code reference.

You can consider _cv2_ is passed to _successor_, then return value of _successor_, forced in scalar-context, is sent by _cv1_.
Actually, there is some treatment for nested call of bind\_scalar/bind\_array.

## bind\_array(_cv1_, _cv2_, _successor_)

Similar as bind\_scalar, but return value of successor is forced in array-context.

# AUTHOR

Yasutaka ATARASHI <yakex@cpan.org>

# COPYRIGHT AND LICENSE

This software is copyright (c) 2012 by Yasutaka ATARASHI.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.
