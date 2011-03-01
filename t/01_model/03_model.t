#!/usr/bin/perl

use strict;
use warnings;

use Test::More tests => 10;
use Test::Exception;

my $module = 'InterMine::Model';

use_ok($module); # Test 1
my $model = new_ok($module => [file => 't/data/testmodel_model.xml']); # Test 2
ok($model->model_name eq 'testmodel', 'Model has the right name'); # Test 3

open (my $fh, '<', 't/data/testmodel_model.xml') or die "Could not open model file";
my $model_xml = join("\n", <$fh>);
close $fh;

my $model2 = new_ok($module => [source => $model_xml]); # test for new lines in strings

like(
    $model->get_classdescriptor_by_name("Employee")->name, 
    qr/^InterMine::testmodel::\d{2}::Employee$/, 
    "The Class has a suitable name"
);

my $test_module= 'InterMine::Model::TestModel';

use_ok($test_module); # Test 4

my $testmodel;

lives_ok {$testmodel = $test_module->instance} 
    "Can get the instance"; # Test 5

like(
    $testmodel->get_classdescriptor_by_name("Employee")->name, 
    qr/^InterMine::TestModel::testmodel::\d{2}::Employee$/, 
    "The Class has a suitable name"
);

# test 6
is($testmodel->model_name, "testmodel", "Model also has the right name");

# test 7
is(scalar($testmodel->get_all_classdescriptors), 19, "Class count ok");

