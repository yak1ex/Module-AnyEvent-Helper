package Module::AnyEvent::Helper::PPI::Transform;

use strict;
use warnings;

# ABSTRACT: PPI::Transform subclass for AnyEvent-ize helper
# VERSION

use base qw(PPI::Transform);

use Carp;

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
    $self->{_TFUNC} = { map { my $func = $_; $func =~ s/^@//; $func, 1 } @{$arg{-translate_func}} } if exists $arg{-translate_func};
    $self->{_AFUNC} = {
        map { my $func = $_; $func =~ s/^@//; $func, 1 }
        exists $arg{-translate_func} ? grep { /^@/ } @{$arg{-translate_func}} : (),
    };
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

sub _find_one_call
{
    my ($word) = @_;
    my ($pre) = [];
    my $sprev_orig = $word->sprevious_sibling;
    my ($prev, $sprev) = ($word->previous_sibling, $word->sprevious_sibling);
    my $state = 'INIT';

# TODO: Probably, this is wrong
    while(1) {
#print STDERR "$state : $sprev\n";
        last unless $sprev;
        if(($state eq 'INIT' || $state eq 'LIST' || $state eq 'TERM' || $state eq 'SUBTERM') && $sprev->isa('PPI::Token::Operator') && $sprev->content eq '->') {
            $state = 'OP';
        } elsif($state eq 'OP' && $sprev->isa('PPI::Structure::List')) {
            $state = 'LIST';
        } elsif(($state eq 'OP' || $state eq 'LIST') && ($sprev->isa('PPI::Token::Word') || $sprev->isa('PPI::Token::Symbol'))) {
            $state = 'TERM';
        } elsif(($state eq 'OP' || $state eq 'SUBTERM') && 
                ($sprev->isa('PPI::Structure::Constructor') || $sprev->isa('PPI::Structure::List') || $sprev->isa('PPI::Structure::Subscript'))) {
            $state = 'SUBTERM';
        } elsif(($state eq 'OP' || $state eq 'SUBTERM') && 
                ($sprev->isa('PPI::Token::Word') || $sprev->isa('PPI::Token::Symbol'))) {
            $state = 'TERM';
        } elsif(($state eq 'OP' || $state eq 'TERM') && $sprev->isa('PPI::Structure::Block')) {
            $state = 'BLOCK';
        } elsif($state eq 'BLOCK' && $sprev->isa('PPI::Token::Cast')) {
            $state = 'TERM';
        } elsif($state eq 'INIT' || $state eq 'TERM' || $state eq 'SUBTERM') {
            last; 
        } else {
            $state = 'ERROR'; last;
        }
        $prev = $sprev->previous_sibling;
        $sprev = $sprev->sprevious_sibling;
    }
    confess "Unexpected token sequence" unless $state eq 'INIT' || $state eq 'TERM' || $state eq 'SUBTERM';
    if($state ne 'INIT') {
        while($sprev ne $sprev_orig) {
            my $sprev_ = $sprev_orig->sprevious_sibling;
            unshift @$pre , $sprev_orig->remove;
            $sprev_orig = $sprev_;
        }
    }
    return [$prev, $pre];
}

sub _replace_as_shift_recv
{
    my ($word) = @_;

    my $args;
    my $next = $word->snext_sibling;

    my ($prev, $pre) = @{_find_one_call($word)};

    if($next && $next->isa('PPI::Structure::List')) {
        my $next_ = $next->next_sibling;
        $args = $next->remove;
        $next = $next_;
    }
    $word->delete;
    _copy_children($prev, $next, $shift_recv);
    return [$pre, $args];
}

my $bind_scalar = PPI::Document->new(\('Module::AnyEvent::Helper::bind_scalar($___cv___, MARK(), sub {'."\n});"))->first_element->remove;
my $bind_array = PPI::Document->new(\('Module::AnyEvent::Helper::bind_array($___cv___, MARK(), sub {'."\n});"))->first_element->remove;

sub _replace_as_async
{
    my ($word, $name, $is_array) = @_;

    my $st = $word->statement;
    my $prev = $word->previous_sibling;
    my $next = $word->next_sibling;

    my ($pre, $args) = @{_replace_as_shift_recv($word)}; # word and prefixes are removed

    # Setup binder
    my $bind_ = $is_array ? $bind_array->clone : $bind_scalar->clone;
    my $mark = $bind_->find_first(sub { $_[1]->class eq 'PPI::Token::Word' && $_[1]->content eq 'MARK'});
    if(defined $args) {
        $mark->next_sibling->delete;
        $mark->insert_after($args);
    }
    $mark->set_content($name);
    while(@$pre) {
        my $entry = pop @$pre;
        $mark->insert_before($entry);
        $mark = $entry;
    }

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

sub _is_array_func
{
    my ($self, $name) = @_;
    return exists $self->{_AFUNC}{$name};
}

sub _is_calling
{
    my ($self, $word) = @_;
    return 0 if ! $word->snext_sibling && ! $word->sprevious_sibling &&
                $word->parent && $word->parent->isa('PPI::Statement::Expression') &&
                $word->parent->parent && $word->parent->parent->isa('PPI::Structure::Subscript');
    return 0 if $word->snext_sibling && $word->snext_sibling->isa('PPI::Token::Operator') && $word->snext_sibling->content eq '=>';
    return 1;
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
            next if ! defined $word->document; # Detached element
            next if ! defined _func_name($word); # Not inside functions / methods
            next if ! $self->_is_translate_func(_func_name($word)); # Not inside target functions / methods
            next if ! $self->_is_calling($word); # Not calling
            my $name = $word->content;
            if($self->_is_replace_target($name)) {
                _replace_as_async($word, $name . '_async', $self->_is_array_func(_func_name($word)));
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

=begin :list

* Emit C<use AnyEvent;use Module::AnyEvent::Helper;> at the beginning of the document.
* Translate (ordinary) methods to _async methods.

=for :list
* Emit C<my $___cv___ = AE::cv;> at the beginning of the methods.
* Emit C<return $___cv___;> at the end of the methods.
* Replace method calls with pairs of C<Module::AnyEvent::Helper::bind_scalar> and C<shift-E<gt>recv>.

* Delete methods you need to implement by yourself.
* Create blocking wait methods from _async methods to emit C<Module::AnyEvent::Helper::strip_async_all();1;> at the end of the packages.

=end :list

This module inherits all of L<PPI::Transform> methods.

=option C<-remove_func>

Specify array reference of removing methods.
If you want to implement async version of the methods, you specify them in this option.

=option C<-translate_func>

Specify array reference of translating methods.
You don't need to implement async version of these methods.
This module translates implementation.

=option C<-replace_func>

Specify array reference of replacing methods.
It is expected that async version is implemented elsewhere.

=option C<-delete_func>

Specify array reference of deleting methods.
If you want to implement not async version of the methods, you specify them in this option.

=head1 METHODS

This module inherits all of L<PPI::Transform> methods.
