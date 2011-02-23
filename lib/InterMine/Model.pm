package InterMine::Model::Handler;

use Carp qw/confess/;
use Scalar::Util qw(weaken);

use InterMine::Model::Attribute;
use InterMine::Model::Reference;
use InterMine::Model::Collection;
use InterMine::Model::ClassDescriptor;

sub new {
    my $class = shift;
    my $self = ( @_ == 0 ) ? shift : {@_};

    return bless $self, $class;
}

sub start_element {
    my $self = shift;
    my $args = shift;

    $self->{current_element} = $args->{Name};

    my $nameattr = $args->{Attributes}{name};

    if ( $args->{Name} eq "model" ) {
        $self->{model}{model_name} = $nameattr;
        my $package_name = $args->{Attributes}{'package'};
        $self->{model}{package_name} = $package_name;
    }
    else {
        my $model = $self->{model};
        if ( $args->{Name} eq "class" ) {
            my @parents = ();
            if ( exists $args->{Attributes}{extends} ) {
                @parents = split /\s+/, $args->{Attributes}{extends};
                @parents = grep { $_ ne 'java.lang.Object' } @parents;

                # strip off any preceding class path (eg. "org.intermine.")
                map { s/.*\.(.*)/$1/ } @parents;
            }
            $self->{current_class} = InterMine::Model::ClassDescriptor->create(
                $nameattr,
                model   => $model,
                parents => [@parents]
            );
            weaken( $self->{current_class}->{model} );
        }
        else {
            my $field;
            if ( $args->{Name} eq "attribute" ) {
                my $type = $args->{Attributes}{type};
                $field = InterMine::Model::Attribute->new(
                    name  => $nameattr,
                    type  => $type,
                    model => $model
                );
            }
            else {
                my $referenced_type = $args->{Attributes}{'referenced-type'};
                my $reverse_reference =
                  $args->{Attributes}{'reverse-reference'};

                my %args = (
                    name                 => $nameattr,
                    referenced_type_name => $referenced_type,
                    model                => $model
                );
                $args{reverse_reference_name} = $reverse_reference
                  if $reverse_reference;

                if ( $args->{Name} eq "reference" ) {
                    $field = InterMine::Model::Reference->new(%args);
                }
                elsif ( $args->{Name} eq "collection" ) {
                    $field = InterMine::Model::Collection->new(%args);
                }
                else {
                    confess "unexpected element: ", $args->{Name}, "\n";
                }

            }
            $field->field_class( $self->{current_class} );
            $self->{current_class}->add_field( $field, 'own' );
        }
    }
}

sub end_element {
    my $self = shift;
    my $args = shift;
    if ( $args->{Name} eq 'class' ) {
        push @{ $self->{classes} }, $self->{current_class};
        $self->{current_class} = undef;
    }
}

1;

package InterMine::Model;

our $VERSION = '0.9600';

=head1 NAME

InterMine::Model - the representation of an InterMine model

=head1 SYNOPSIS

  use InterMine::Model;

  my $model_file = 'flymine/dbmodel/build/model/genomic_model.xml';
  my $model = InterMine::Model->new(file => $model_file);
  my $gene = $model->make_new(
    Gene => {
        primaryIdentifier => "FBgn0004053",
        secondaryIdentifier => "CG1046",
        symbol              => "zen",
        name                => "zerknullt",
        length              => "3474",
        organism            => {
            shortName => "D. melanogaster",
        }
        ncbiGeneNumber      => 40828,
    });

  $gene->getName(); # "zerknullt"

  ...

=head1 DESCRIPTION

The class is the Perl representation of an InterMine data model.  The
new() method can parse the model file.  The
get_classdescriptor_by_name() method will return an
InterMine::Model::ClassDescriptor object for the class with the given
name.

For an example model see:
http://trac.flymine.org/browser/trunk/intermine/objectstore/model/testmodel/testmodel_model.xml

=head1 AUTHOR

FlyMine C<< <support@flymine.org> >>

=head1 BUGS

Please report any bugs or feature requests to C<support@flymine.org>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc InterMine::Model;

You can also look for information at:

=over 4

=item * FlyMine

L<http://www.flymine.org>

=back

=head1 COPYRIGHT & LICENSE

Copyright 2006,2007,2008,2009 FlyMine, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 FUNCTIONS

=cut

use strict;
use Carp qw/confess/;
use Moose::Util::TypeConstraints;

use constant TYPE_PREFIX => "InterMine";

=head2 new

 Title   : new
 Usage   : $model = new InterMine::Model(file => $model_file);
             or
           $model = new InterMine::Model(string => $model_string);
 Function: return a Model object for the given file
 Args    : file - the InterMine model XML file

=cut

sub new {
    my $class = shift;
    my %opts  = @_;
    my $self  = {%opts};

    if ( !defined $opts{file} && !defined $opts{string} ) {
        confess "$class\::new() needs a file or string argument\n";
    }
    elsif ( defined $opts{file} && !-f $opts{file} ) {
        confess "A valid file must be specified: we got $opts{file}\n";
    }

    $self->{class_hash} = {};

    bless $self, $class;

    #my $self = Object::Destroyer->new($self, 'release');

    if ( defined $opts{file} ) {
        $self->_process( $opts{file}, 0 );
    }
    else {
        $self->_process( $opts{string}, 1 );
    }


    $self->_fix_class_descriptors();

    return $self;
}

use XML::Parser::PerlSAX;

sub _process {
    my $self             = shift;
    my $source_arg       = shift;
    my $source_is_string = shift;

    my $handler = new InterMine::Model::Handler( model => $self );
    my $parser = XML::Parser::PerlSAX->new( Handler => $handler );

    my $source;

    if ($source_is_string) {
        $source = { String => $source_arg };
    }
    else {
        $source = { SystemId => $source_arg };
    }

    $parser->parse( Source => $source );

    $self->{classes} = $handler->{classes};

    for my $class ( @{ $self->{classes} } ) {
#        my $classname = $class->name();
        $self->{class_hash}{$class} = $class;
    }
}

sub _add_type_constraint_and_coercion {
    my $self = shift;
    my $class_name = shift;

    subtype $class_name, as "Object", where {$_->isa($class_name)};
    subtype "ArrayOf" . $class_name, as "ArrayRef[$class_name]";
    coerce $class_name, from 'HashRef', via {
        $self->make_new(($_->{class} || $class_name), $_);
    };
    subtype "ArrayOfHashes", as "ArrayRef[HashRef]";

    coerce "ArrayOf$class_name", from "ArrayOfHashes", 
        via { [map {$self->make_new(($_->{class} || $class_name), $_)} @$_] };
}

# add fields from base classes to sub-classes so that $class_descriptor->fields()
# returns fields from base classes too
sub _fix_class_descriptors {
    my $self = shift;

    for my $class_name (keys %{ $self->{class_hash} } ) {
        $self->_add_type_constraint_and_coercion($class_name);
    }

    while ( my ( $class_name, $cd ) = each %{ $self->{class_hash} } ) {
        my @fields = $self->_get_fields($cd);
        for my $field (@fields) {
            $cd->add_field($field);
        }
        $cd->_make_fields_into_attributes();
    }
}

sub _get_fields {
    my $self = shift;
    my $cd   = shift;

    my @fields = ();

    for my $field ( $cd->fields() ) {
        my $field_name = $field->name();
        push @fields, $field;
    }

    for my $parent ( $cd->parental_class_descriptors ) {
        push @fields, $self->_get_fields($parent);
    }

    return @fields;
}

=head2 get_classdescriptor_by_name

 Title   : get_classdescriptor_by_name
 Usage   : $cd = $model->get_classdescriptor_by_name("Gene");
 Function: return the InterMine::Model::ClassDescriptor for the given class or
           undef if the class isn't in the model
 Args    : the classname

=cut

sub get_classdescriptor_by_name {
    my $self      = shift;
    my $classname = shift;
    if ( !defined $classname ) {
        confess "no classname passed to get_classdescriptor_by_name()\n";
    }

    # These are always valid
    if ( $classname eq 'Integer' ) {
        return InterMine::Model::ClassDescriptor->new(
            model   => $self,
            name    => $classname,
            extends => ['id'],
        );
    }

    my $class = $self->{class_hash}{$classname}
      || $self->{class_hash}{ $self->{package_name} . $classname };
    confess "$classname not in the model" unless $class;
    return $class;
}

=head2 make_new($class_name, [%attributes|$attributes])

Return an object of the desired class, with the attributes 
given

 my $gene = $model->make_new(Gene => {symbol => "zen", organism => {name => 'D. melanogaster}});

 say $gene->get_symbol             # "zen"
 say $gene->get_organism->get_name # "D. melanogaster"

=cut

sub make_new {
    my $self = shift;
    my $name = (ref $_[0] eq 'HASH') ? $_[0]->{class} : shift;
    my $params = (@_ == 1) ? $_[0] : {@_};

    return $self->get_classdescriptor_by_name($name)->new_object($params);
}

=head2 get_all_classdescriptors

 Title   : get_all_classdescriptors
 Usage   : @cds = $model->get_all_classdescriptors();
 Function: return all the InterMine::Model::ClassDescriptor objects for this
           model
 Args    : none

=cut

sub get_all_classdescriptors {
    my $self = shift;
    return values %{ $self->{class_hash} };
}

=head2 get_referenced_classdescriptor

 Usage    : my $cd = $model->get_referenced_classdescriptor($ref);
 Function : get the class descriptor at the other end of a reference
 Args     : The reference

=cut

sub get_referenced_classdescriptor {
    my $self      = shift;
    my $reference = shift;
    for my $cd ( $self->get_all_classdescriptors ) {
        for my $ref ( $cd->references ) {
            if ( $ref->has_reverse_reference ) {
                if ( $ref->reverse_reference->name eq $reference ) {
                    return $cd;
                }
            }
        }
    }
    return undef;
}

=head2 find_classes_declaring_field

 Usage    : my @classes = $model->find_classes_declaring_field($str);
 Function : get the class descriptors that declare fields of a certain name  
 Args     : The field's name

=cut

sub find_classes_declaring_field {
    my $self       = shift;
    my $field_name = shift;
    my @returners;
    for my $cd ( $self->get_all_classdescriptors ) {
        for my $field ( $cd->get_own_fields ) {
            push @returners, $cd if ( $field->name eq $field_name );
        }
    }
    return @returners;
}

=head2 package_name

 Title   : package_name
 Usage   : $package_name = $model->package_name();
 Function: return the package name derived from the name space
           eg. "org.intermine.model"
 Args    : none

=cut

sub package_name {
    my $self = shift;
    return $self->{package_name};
}

=head2 model_name

 Title   : model_name
 Usage   : $model_name = $model->model_name();
 Function: return the model name from the model file eg. "testmodel"
 Args    : none

=cut

sub model_name {
    my $self = shift;
    return $self->{model_name};
}

1;
