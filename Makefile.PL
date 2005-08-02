# $Id: Makefile.PL,v 1.1 2005/08/01 18:25:32 esobchenko Exp $

use ExtUtils::MakeMaker;

WriteMakefile (

	'NAME' => 'Object::Mediator',
	'VERSION_FROM' => 'lib/Object/Mediator.pm',
	'PREREQ_PM' => {
		'Test::More' => '0.45',
		'Class::Accessor' => '0.19',
		'Class::Data::Inheritable' => '0.02',
	},

);
