package Module::AnyEvent::Helper::PPI::Transform;

use strict;
use warnings;

# VERSION

use base qw(PPI::Transform);

sub new
{
    my $self = shift;
    my $class = ref($self) || $self;
    my %arg = @_;
    $self = bless {
    }, $class;
    $self->{_PFUNC} = { map { $_, 1 } @{$arg{-replace_func}} } if exists $arg{-replace_func};
    $self->{_RFUNC} = { map { $_, 1 } @{$arg{-remove_func}} } if exists $arg{-remove_func};
    $self->{_DFUNC} = { map { $_, 1 } @{$arg{-delete_func}} } if exists $arg{-delete_func};
    $self->{_TFUNC} = { map { $_, 1 } @{$arg{-translate_func}} } if exists $arg{-translate_func};
    return $self;
}

sub _func_name
{
    my $word = shift;
    my $st = $word->statement;
    return if ! $st;
    return _func_name($st->parent) if $st->class ne 'PPI::Statement::Sub';
    return $st->schild(1);
}

sub _is_func_decl
{
    my $word = shift;
    return defined $word->parent && $word->parent->class eq 'PPI::Statement::Sub';
}

sub _delete_func_decl
{
    my $word = shift;
    return $word->parent->delete;
}

sub _copy_children
{
    my ($prev, $next, $target) = @_;

    for my $elem ($target->children) {
        my $new_elem = $elem->clone or die;
        if($prev) {
            $prev->insert_after($new_elem) or die;
        } else {
            $next->insert_before($new_elem) or die;
        }
        $prev = $new_elem;
    }
}

my $cv_decl = PPI::Document->new(\'my $___cv___ = AE::cv;')->first_element->remove;

sub _emit_cv_decl
{
    my $word = shift;
    my $block = $word->parent->find_first('PPI::Structure::Block');
    _copy_children($block->first_element, undef, $cv_decl);
}

my $cv_ret = PPI::Document->new(\'return $___cv___;'); #->first_element->remove;

sub _emit_cv_ret
{
    my $word = shift;
    my $block = $word->parent->find_first('PPI::Structure::Block');
    _copy_children($block->schild($block->schildren-1), undef, $cv_ret);
}

my $shift_recv = PPI::Document->new(\'shift->recv()')->first_element->remove;

sub _replace_as_shift_recv
{
    my ($word) = @_;

    my $args;
    my $prev = $word->previous_sibling;
    my $next = $word->next_sibling;

    if($next && $next->isa('PPI::Structure::List')) {
        my $next_ = $next->next_sibling;
        $args = $next->remove;
        $next = $next_;
    }
    $word->delete;
    _copy_children($prev, $next, $shift_recv);
    return $args;
}

my $bind = PPI::Document->new(\('Module::AnyEvent::Helper::bind_scalar($___cv___, MARK(), sub {'."\n});"))->first_element->remove;

sub _replace_as_async
{
    my ($word, $name) = @_;

    my $st = $word->statement;
    my $prev = $word->previous_sibling;
    my $next = $word->next_sibling;

    my $args = _replace_as_shift_recv($word); # word is removed

    # Setup binder
    my $bind_ = $bind->clone;
    my $mark = $bind_->find_first(sub { $_[1]->class eq 'PPI::Token::Word' && $_[1]->content eq 'MARK'});
    if(defined $args) {
        $mark->next_sibling->delete;
        $mark->insert_after($args);
    }
    $mark->set_content($name);

    # Insert
    $st->insert_before($bind_);

    # Move statements into bound closure
    my $block = $bind_->find_first('PPI::Structure::Block');
    do { # Move statements into bound closure
        $next = $st->next_sibling;
        $block->add_element($st->remove);
        $st = $next;
    } while($st);
}

my $use = PPI::Document->new(\"use AnyEvent;use Module::AnyEvent::Helper;");

sub _emit_use
{
    my ($doc) = @_;
    my $first = $doc->first_element;
    $first = $first->snext_sibling if ! $first->significant;
    _copy_children(undef, $first, $use);
}

my $strip = PPI::Document->new(\"Module::AnyEvent::Helper::strip_async_all();1;");

sub _emit_strip
{
    my ($doc) = @_;
    my $pkgs = $doc->find('PPI::Statement::Package');
    shift @{$pkgs};
    for my $pkg (@$pkgs) {
        _copy_children(undef, $pkg, $strip);
    }
    my $last = $doc->last_element;
    $last = $last->sprevious_sibling if ! $last->significant;
    _copy_children($last, undef, $strip);
}

sub _is_translate_func
{
    my ($self, $name) = @_;
    return exists $self->{_TFUNC}{$name};
}

sub _is_remove_func
{
    my ($self, $name) = @_;
    return exists $self->{_RFUNC}{$name};
}

sub _is_replace_func
{
    my ($self, $name) = @_;
    return exists $self->{_PFUNC}{$name};
}

sub _is_delete_func
{
    my ($self, $name) = @_;
    return exists $self->{_DFUNC}{$name};
}

sub _is_replace_target
{
    my ($self, $name) = @_;
    return $self->_is_translate_func($name) || $self->_is_remove_func($name) || $self->_is_replace_func($name);
}

sub document
{
    my ($self, $doc) = @_;
    $doc->prune('PPI::Token::Comment');

    _emit_use($doc);
    _emit_strip($doc);

    my @decl;
    my $words = $doc->find('PPI::Token::Word');
    for my $word (@$words) {
        next if !defined($word);
        if(_is_func_decl($word)) { # declaration
            if($self->_is_remove_func($word->content) || $self->_is_delete_func($word->content)) {
                _delete_func_decl($word);
            } elsif($self->_is_translate_func($word->content)) {
                push @decl, $word; # postpone declaration transform because other parts depend on this name
                _emit_cv_decl($word);
            }
        } else {
            next if ! defined $word->document;
            next if ! defined _func_name($word);
            next if ! $self->_is_translate_func(_func_name($word));
            my $name = $word->content;
            if($self->_is_replace_target($name)) {
                _replace_as_async($word, $name . '_async');
            }
        }
    }
    foreach my $decl (@decl) {
        $decl->set_content($decl->content . '_async');
        _emit_cv_ret($decl);
    }
    return 1;
}

1;
__END__
=pod

=head1 NAME

Module::AnyEvent::Helper::PPI::Transform - PPI::Transform subclass for AnyEvent-ize helper

=head1 SYNOPSIS

Typically, this module is not used directly but used via L<Module::AnyEvent::Helper::Filter>.
Of course, however, you can use this module directly. 

  my $trans = Module::AnyEvent::Helper::PPI::Transform->new(
      -remove_func => [qw()],
      -translate_func => [qw()]
  );
  $trans->file('Input.pm' => 'Output.pm');

NOTE that this module itself does not touch package name.

=head1 DESCRIPTION

To make some modules AnyEvent-frinedly, it might be necessary to write boiler-plate codes.
This module applys the following transformations.

=over 4

=item *

Emit C<use AnyEvent;use Module::AnyEvent::Helper;> at the beginning of the document.

=item *

Translate (ordinary) methods to _async methods.

=over 4

=item *

Emit C<my $___cv___ = AE::cv;> at the beginning of the methods.

=item *

Emit C<return $___cv___;> at the end of the methods.

=item *

Replace method calls with pairs of C<Module::AnyEvent::Helper::bind_scalar> and C<shift-E<gt>recv>.

=back

=item *

Delete methods you need to implement by yourself.

=item *

Create blocking wait methods from _async methods to emit C<Module::AnyEvent::Helper::strip_async_all();1;> at the end of the packages.

=back

=head1 OPTIONS

=over 4

=item C<-remove_func>

Specify array reference of removing methods.
If you want to implement async version of the methods, you specify them in this option.

=item C<-translate_func>

Specify array reference of translating methods.
You don't need to implement async version of these methods.
This module translates implementation.

=item C<-replace_func>

Specify array reference of replacing methods.
It is expected that async version is implemented elsewhere.

=item C<-delete_func>

Specify array reference of deleting methods.
If you want to implement not async version of the methods, you specify them in this option.

=back

=head1 METHODS

This module inherits all of L<PPI::Transform> methods.

=head1 AUTHOR

Yasutaka ATARASHI <yakex@cpan.org>

=head1 LICENSE

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut
