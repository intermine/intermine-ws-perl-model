package InterMine::Model::ClassDescriptor;

=head1 NAME

InterMine::Model::ClassDescriptor - represents a class in an InterMine model

=head1 SYNOPSIS

 use InterMine::Model::ClassDescriptor;

 ...
 my $cd = InterMine::Model::ClassDescriptor->create(
            "Gene" => (
                model => $model,
                parents => ["BioEntity"]
            )
        );

=head1 DESCRIPTION

Objects of this class contain the metadata that describes a class in an
InterMine model.  Each class has a name, parent classes/interfaces and any
number of attributes, references and collections. 

InterMine class descriptors are sub classes of L<Moose::Meta::Class>, and thus
L<Class::MOP::Class>. Please refer to these packages for further documentation.

=head1 CLASS METHODS

=cut

use Moose;
extends qw/Moose::Meta::Class/;
with 'InterMine::Model::Role::Descriptor';
use InterMine::TypeLibrary qw(
    FieldList FieldHash ClassDescriptorList ClassDescriptor BigInt
);
use MooseX::Types::Moose qw(ArrayRef Str Bool);
use Moose::Util::TypeConstraints;
use Scalar::Util qw(refaddr);

=head2 create( $name | $name, %attributes | $name, \%attributes | \%attributes )

The class constructor inherited from L<Moose::Meta::Class>.

 Usage   : my $cd = InterMine::Model::ClassDescriptor->create(
                "Gene" => (
                    model => $model,
                    parents => ["BioEntity"]
                )
            );

 Function: create a new ClassDescriptor object
 Args    : model   - the InterMine::Model that this class is a part of
           name    - the class name
           parents - a list of the classes and interfaces that this classes
                     extends

In most normal use cases, the typical user should not need to call this method. 
It is used internally when parsing the model to build up the list of classes.

=cut

# Make class a synonym for meta in the instantiated object

override 'create' => sub {
    my $class = shift;
    my $ret = super;
    $ret->add_method("class", sub {my $self = shift; return $self->meta});
    $ret->add_attribute(
        objectId => {
            reader => "getObjectId",
            predicate => "hasObjectId",
            isa => Str,
        }
    );
    return $ret;
};

# and make name a synonym for package here.

=head2 name | package

return the name of the class this class descriptor represents. Package
is the attribute inherited from Moose::Meta::Class

 Usage   : $name = $cd->name();
 Function: Return the name of this class, eg. "Gene"
 Args    : none

=cut

has '+name' => (
    lazy => 1,
    default => sub { shift->package },
);

=head2 own_fields

The list of fields that were declared in this class (not inherited from 
elsewhere), it has the following accessors:

=head3 add_own_field($field)

Add a field to the list

=head3 get_own_fields 

Get the full list of fields declared in this class.

=cut 

has own_fields => (
    traits => ['Array'],
    is	    => 'ro',
    isa	    => FieldList,
    default => sub { [] },
    handles => {
	add_own_field  => 'push',
	get_own_fields => 'elements',
    },
);

=head2 fieldhash

The map of fields for this class. It has the following accessors:

=head3 set_field($name, $field)

Set a field in the map

=head3 get_field_by_name($name)

Retrieve the named field.

=head3 fields

Retrieve all fields as a list

=head3 valid_field($name)

Returns true if there is a field of this name 

=cut

has fieldhash => (
    traits  => [qw/Hash/],
    is	    => 'ro',
    isa	    => FieldHash,
    default => sub { {} },
    handles => {
	set_field	  => 'set',
	get_field_by_name => 'get',
	fields		  => 'values',
	valid_field       => 'defined',
    },
);

=head2 parents 

The immediate ancestors of this class.

 Usage   : @parent_class_names = $cd->parents();
 Function: return a list of the names of the classes/interfaces that this class
           directly extends
 Args    : none

=cut

has parents => (
    is	       => 'ro',
    isa	       => ArrayRef[Str],
    auto_deref => 1,
);

=head2 parental_class_descriptors

The parents as a list of class objects.

 Usage   : @parent_cds = $cd->parental_class_descriptors();
 Function: return a list of the ClassDescriptor objects for the
           classes/interfaces that this class directly extends
 Note    : Calling this method retrives the parents from the model
           and also sets up superclass relationships
           in Moose. It should not be called until the Model is completely
           parsed. It is called automatically once the model has been 
           parsed.
 Args    : none

=cut

has parental_class_descriptors => (
    is	       => 'ro',
    isa	       => ClassDescriptorList,
    lazy       => 1,
    auto_deref => 1,
    default => sub {
        my $self = shift;
        $self->superclasses($self->parents);
        return [
            map {$self->model->get_classdescriptor_by_name($_)} $self->parents
        ];
    },
);

=head2 ancestors

The full inheritance list, including all ancestors in the model.

=cut

has ancestors => (
    reader     => 'get_ancestors',
    isa	       => ClassDescriptorList,
    lazy       => 1,
    auto_deref => 1,
    default => sub {
	my $self = shift;
	my @inheritance_path = ($self,);
	my @classes = $self->parental_class_descriptors();
	for my $class (@classes) {
	    push @inheritance_path, $class->get_ancestors;
	}
	return \@inheritance_path;
    },
);


has package => (
    is      => 'ro',
    isa     => 'Str',
    default => sub { shift->name }
);

=head2 add_field

 Usage   : $cd->add_field($field);
 Function: add a Field to this class
 Args    : $field - a sub class of InterMine::Model::Field

=cut

# see also: Model->_fix_class_descriptors()
sub add_field {
  my ($self, $field, $own)  = @_;

  return if defined $self->get_field_by_name($field->name);

  $self->set_field($field->name, $field);
  $self->add_own_field($field) if $own;
}

sub _make_fields_into_attributes {
    my $self   = shift;
    my @fields = $self->fields;

    for my $field (@fields) {
        my $suffix = ucfirst($field->name);
        my $get = $field->_type_is(Bool)  ? "is" : "get";
        my $options = {
            reader    => $get  . $suffix,
            writer    => "set" . $suffix,
            predicate => "has" . $suffix,
            $field->_get_moose_options,
        };

        $self->add_attribute($field->name, $options);
    }
}

=head2 attributes

 Usage   : @fields = $cd->attributes();
 Function: Return the Attribute objects for the attributes of this class
 Args    : none

=cut

sub attributes {
    my $self = shift;
    return grep {$_->isa('InterMine::Model::Attribute')} $self->fields;
}

=head2 references

 Usage   : @fields = $cd->references();
 Function: Return the Reference objects for the references of this class
 Args    : none

=cut

sub references {
    my $self = shift;
    return grep {$_->isa('InterMine::Model::Reference')} $self->fields;
}

=head2 collections

 Usage   : @fields = $cd->collections();
 Function: Return the Collection objects for the collections of this class
 Args    : none

=cut

sub collections {
    my $self = shift;
    return grep {$_->isa('InterMine::Model::Collection')} $self->fields;
}

=head2 sub_class_of

 Usage   : if ($class_desc->sub_class_of($other_class_desc)) { ... }
 Function: Returns true if and only if this class is a sub-class of the given
           class or is the same class
 Args    : $other_class_desc - a ClassDescriptor

=cut

sub sub_class_of
{
  my $self = shift;
  my $other_class_desc = shift;

  if ($self eq $other_class_desc) {
    return 1;
  } else {
    for my $parent ($self->parental_class_descriptors()) {
      if ($parent->sub_class_of($other_class_desc)) {
        return 1;
      }
    }
  }
  return 0;
}

1;

=head1 SEE ALSO

=over 4

=item * L<Moose::Meta::Class>

=back

=head1 AUTHOR

FlyMine C<< <support@flymine.org> >>

=head1 BUGS

Please report any bugs or feature requests to C<support@flymine.org>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc InterMine::Model::ClassDescriptor

You can also look for information at:

=over 4

=item * FlyMine

L<http://www.flymine.org>

=back

=head1 COPYRIGHT & LICENSE

Copyright 2006,2007,2008,2009 FlyMine, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

