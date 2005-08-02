# $Id: 01sanity.t,v 1.1 2005/08/01 18:25:40 esobchenko Exp $

##
## basic sanity
##

package Persistent;

use base qw( Object::Mediator );

__PACKAGE__->mk_attr ( qw(foo bar baz) );

sub _set_id {
	my $self = shift;

	$self->identity ( 123 );
}

1;

use Test::More qw(no_plan);

#
# new()
#

my $obj1 = Persistent->new ( 
	'foo' => 'aaa',
	'bar' => 'bbb',
);

# new returned something
ok ( defined $obj1 );

# this something is Persistent's class object
ok ( $obj1->isa ( 'Persistent' ) );

# identity is 10
ok ( 123 == $obj1->id() );

# N/N state
ok ( $obj1->is_new );
ok ( not $obj1->is_updated );


#
# accessors - set()
#

ok ( $obj1->can( 'foo' ) );
ok ( $obj1->can( 'bar' ) );

is ( $obj1->foo(), 'aaa' );
is ( $obj1->bar(), 'bbb' );

$obj1->foo ( 'ccc' );
$obj1->bar ( 'ddd' );

ok ( $obj1->is_new );

#
# retrieve()
#

my $obj2 = Persistent->retrieve ( $obj1->id );

# new returned something
ok ( defined $obj2 );

# this something is Persistent's class object
ok ( $obj2->isa ( 'Persistent' ) );

ok ( not $obj2->is_updated );

#
# update()
#

$obj1->update();

# N/U state
ok ( $obj2->is_updated and $obj1->is_updated );


#
# weak refs
#

ok ( $obj2->foo('eee') );
ok ( $obj2->bar('fff') );

is ( $obj2->foo, $obj1->foo );
is ( $obj2->bar, $obj1->bar );

ok ( $obj1->is_modified );
ok ( not $obj1->is_updated );

#
# delete ()
#

$obj1->delete();

ok ( $obj2->is_deleted );
ok ( not $obj2->is_updated );

