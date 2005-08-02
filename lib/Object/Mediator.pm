#
# $Id: Mediator.pm,v 1.1 2005/07/30 09:15:30 esobchenko Exp $

# Simple Object Persistence
package Object::Mediator;

use strict;
use Carp;

use Scalar::Util qw(weaken);
use Class::Accessor;

use base qw(
	Class::Accessor
	Class::Data::Inheritable
);

# $Date: 2005/07/30 09:15:30 $
our $VERSION = '0.01';

# object state constants
use constant {
	NEW => 0,
	DELETED => 1,
	MODIFIED => 2,
};

#
# Class data
#
__PACKAGE__->mk_classdata ( 'purge_object_index_every' );
__PACKAGE__->purge_object_index_every ( 1000 );

__PACKAGE__->mk_classdata ( 'object_autoupdate' );
__PACKAGE__->object_autoupdate ( 1 );

*mk_attributes = \&Class::Accessor::mk_accessors;
*mk_attr = \&mk_attributes;

#
# status check accessors
#
sub is_new () { NEW == shift->_status() }
sub is_deleted () { DELETED == shift->_status() }
sub is_modified () { MODIFIED == shift->_status() }

sub _status {
	my ( $self, $status, $updated ) = @_;

	if ( defined $status ) {
		$self->{'_status'} = $status;
		$self->_updated( defined $updated ? 1 : 0 );
	}

	return $self->{'_status'};
}

#
# object memory state check accessos
#
sub is_updated () { shift->{'_updated'} }

sub _updated {
	my $self = shift;
	$self->{'_updated'} = @_ ? $_[0] : 1;
}

#
# object index keeps live objects in memory using weak refs
#
my %live_objects = ();
my $count = 0; # indexed objects counter

sub index_object {
	my $self = shift;

	my $class = $self->_class;
	weaken ( $live_objects{ $self->identity } = $self );
	# is it time to purge index from dead objects?
	$class->purge_dead_from_object_index
		if ++$count % $class->purge_object_index_every == 0;

	return 1;
}

sub purge_dead_from_object_index {
	# delete undefined object references
	delete @live_objects{ grep !defined $live_objects{$_}, keys %live_objects };
}

sub retrieve_indexed {
	my ( $class, $id ) = @_;

	my $object = undef;
	$object = $live_objects{$id} if ( exists $live_objects{$id} );

	return $object;
}

sub delete_indexed {
	my ( $class, $id ) = @_;
	delete $live_objects{$id};
}

sub identity {
	my $self = shift;

	# identity means to be set only once!
	if ( @_ and (not defined $self->{'_identity'}) ) {
		$self->{'_identity'} = shift;
	}

	return $self->{'_identity'};
}

*id = \&identity;

sub autoupdate {
	my $self = shift;

	if ( @_ ) {
		$self->{'_autoupdate'} = shift;
	}

	return $self->{'_autoupdate'};
}

sub attr_modified {
	my $self = shift;

	wantarray ? keys %{ $self->{'_attr_modified'} } :
		[ keys %{ $self->{'_attr_modified'} } ];
}

#
# Overloading Class::Accessor's set()/get() methods
# to change accessors behavior according our needs
#
sub set {
	my ( $self, $key ) = splice ( @_, 0, 2 );

	if ( $self->is_updated ) {
		$self->_status ( $self->is_deleted ? NEW : MODIFIED );
	} else {
		$self->_status ( MODIFIED ) if $self->is_deleted;
	}

	# registering object's attribute modification here
	${ $self->{'_attr_modified'} }{$key} = time();
	$self->SUPER::set( $key, @_ );
}

#sub get {
#	my ( $self, $key ) = splice ( @_, 0, 2 );

#	croak (
#		sprintf "cannot get %s field value, %s object is deleted",
#			$key, $self->_class
#	) if $self->is_deleted;

#	$self->SUPER::get( $key );
#}

sub new {
	my $class = shift;

	my $self = {
		'_identity' => undef,

		@_,

		'_autoupdate' => $class->object_autoupdate,
		'_attr_modified' => {},
		'_status' => NEW,
		'_updated' => 0,
	};

	bless $self, $class;

	$self->_set_id unless defined $self->identity;

	croak sprintf "%s object identity is not set!", $class
		unless defined $self->identity;

	$self->index_object;

	return $self;
}

sub retrieve {
	my ( $class, $id ) = @_;

	my $self;

	unless ( defined ( $self = $class->retrieve_indexed($id) ) ) {
		# object isn't indexed, retrieving from database
		$self = $class->new( _identity => $id );
		$self->_select();
		$self->_updated(1);
	}

	return $self;
}

sub delete () {
	my $self = shift;

	unless ( ref $self ) {
		# XXX Its expensive to retrieve object every time delete()
		# invoked as class method. Should be fixed.
		$self->retrieve( shift )->delete();
	}

	return 1 if $self->is_deleted; # already deleted

	do {
		$self->_status ( DELETED, 1 );
		return 1;
	} if ( not $self->is_updated and $self->is_new );

	$self->_status( DELETED );
	return 1;
}

*remove = \&delete;

# update database with object's in-memory state
sub update () {
	my $self = shift;

	return if $self->is_updated;

	if ( $self->is_new ) {
		$self->_insert
	} elsif ( $self->is_deleted ) {
		$self->_delete
	} elsif ( $self->is_modified ) {
		$self->_update
	}

	$self->_updated(1);
	return 1;
}


# destructor
sub DESTROY {
	my $self = shift;
	$self->update if $self->autoupdate;
	return 1;
}

sub _class { return ref $_[0] || shift }

#
# dummy methods. must be overloaded in child classes
#
sub _set_id { 1 }

sub _select { 1 }

sub _insert { 1 }

sub _delete { 1 }

sub _update { 1 }

1;


__END__


=head1 NAME

Object::Mediator - generic object persistence framework

=head1 SYNOPSIS

	package Persistent;

	use base qw( Object::Mediator );

	__PACKAGE__->mk_attr ( foo bar baz );

	sub _set_id {
		my $self = shift;

		$self->generate_identity();
	}

	sub _insert {
		my $self = shift;

		$self->insert_in_database();
	}

	sub _update {
		my $self = shift;

		$self->update_in_database();
	}

	sub _delete {
		my $self = shift;

		$self->delete_from_database();
	}

	sub _select {
		my $self = shift;

		$self->select_from_database();
	}

=head1 DESCRIPTION

Object::Mediator attempts to be simple and fairly minimalistic object mapping
framework. Main aims of development were: usage simplicity, end user transparency,
database independency and minimization of database interaction with some
kind of in-memory object state control system.

=head2 Usage simplicity

The basic steps to make your objects persistent are:

	1. Inherit from Object::Mediator,
	2. Set up attributes to map with mk_attr() function,
	3. Describe mapping procedures

There are five mapping procedures you need to define in your
module. All of them are object methods which called automatically,
as a rule when object is destroyed or when the update() method is invoked
manually. Here is details below:

=over 2

=item _set_id()

Sets object identity. Called once when new object is created.

=cut

=item _select()

Retrieves object from database and sets appropriate attributes.

=cut

=item _insert()

Creates object in persistent storage.

=cut

=item _delete()


Deletes object from persistent storage.

=cut

=item _update()

Update database with object's current in-memory state.

=cut

=back

Now you will able to use your module and create persistent objects:

	use Persistent; # your module

	my $object = Persistent->new (
		foo => 'bazooka',
		bar => 'uzi',
	);

	$object->baz ( 'shotgun' );

Voila!

=head2 End user transparency

Object::Mediator based classes are completely transparent to the end user.
All operations with object persistent storage are performed implicitly.

=head2 Database independency

Object::Mediator implements mapping by means of procedures described by you.
So there are no limitations in using any DBMS/interface that you want to set for
persistent storage for objects of your class.

=head2 Minimization of database interaction

It seems obvious that there is no need to perform mapping every time object
changes in memory. It has sense to invoke synchronization only if necessary
and after work with the object is completed. Object::Mediator object state
set is provided to implement this effective mapping. All objects stay in one
of three states - NEW, MODIFIED or DELETED which determines (implies)
corresponding procedure invokation when mapping is executed. There is also
UPDATED flag for all of those states to prevent recurring database calls.
It sets by update() method after synchronization finished and testifies
completeness of the object mapping. Here is a transition table:

            | State
      Event |  N/U     N/N     D/U     D/N     M/U     M/N
     -------+-------+-------+-------+-------+-------+-------+
     new()  |  N/N      -      N/N     N/N     N/N     N/N
  delete()  |  D/N     D/U      -       -      D/N     D/N
     set()  |  M/N      -      N/N     M/N     M/N      -

I<State> row enumerates possible object states. I<Event> column lists
actions/methods which affect on object's state. Note: as it will be descibed below
the accessor methods (which are named same as attributes) are built up using
Class::Accessor package, so all of them use set() method to perform object
attribute value changes.

Furthermore, Object::Mediator supports uniqueness of objects in memory. In a given
perl interpreter there will only be one instance of any given object at one time.
This is implemented using a simple object lookup index with weak references
for all live objects in memory. It is not a traditional cache - when your objects
go out of scope, they will be destroyed normally, and a future retrieve will
instantiate an entirely new object. Refer to Scalar::Util::weaken function
specification for details. The idea was inherited from Class::DBI module.

=head1 METHODS

=head2 Class methods

Following class methods are available:

=head3 mk_attr(@fields)

This creates accessor/mutator methods for each named field given in @fields using
Class::Accessor module which is inherited by default. Functions mk_attributes()
and mk_accessors() are aliases.

=head3 new(%attr)

Object constructor to create new object. Initial values for object attributes
can be set thru %attr hash. _set_id() method is called implicitly within
new() to set identity for newly created object.

=head3 retrieve($id)

Retrieves object by identity passed thru $id.

=head3 delete($id)

Deletes object by identity.

=head3 object_autoupdate($on_or_off)

Sets default value for new object's autoupdate attribute. If I<off> - update()
method is not executed during DESTROY(). Can be changed for object idividually
using autoupdate() object method. Default value: I<on>

=head3 purge_object_index_after()

Weak references are not removed from the index when an object goes out of scope.
This means that over time the index will grow in memory. This is really only an issue
for long-running environments like mod_perl, but every so often we go through
and clean out dead references to prevent it. By default, this happens evey
1000 object loads, but you can change that default for your class by calling
the purge_object_index_every() method with a number.

=head2 Object methods

Following object methods are available:

=head3 identity()

Returns unique identifier of this object. Object identifier should
be set by identity() only once, usually in _set_id(). Synonym: id().

=head3 delete()

Marks current object as deleted.

=head3 update()

Performs appropriate mapping procedure for current object.

=head3 attr_modified()

Returns list of arguments which are modified.

=head3 set()

Overloaded Class::Accessor's set().

=head3 get()

Overloaded Class::Accessor's get().

=head1 AUTHOR

Eugen J. Sobchenko <esobchenko@gmail.com>

=head1 SEE ALSO

Currently working on some-kind of homepage for this module.

Class::DBI is a perfect analogue for object-relational mapping
from which lot of solutions were inherited.

=head1 COPYRIGHT

Copyright (c) 2004-2005 Eugen J. Sobchenko. All rights reserved.
This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

