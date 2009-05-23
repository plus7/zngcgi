package Zng::Net::Map;

use strict;
use IO::Poll qw{POLLIN};
use Net::DNS;

my $PACKAGE = __PACKAGE__;

sub new ( $$$ ) {
    my $class = shift;
    my $net = shift;
    my $name = shift;

    my $resolver = Net::DNS::Resolver->new;
    my $self = {
	net => $net,
	resolver => $resolver,
	listeners => [],
	addr => undef,
	errorstring => undef,
    };
    bless $self, $class;

    my $handle = $resolver->bgsend($name);
    unless ($handle) {
	$self->__abort("$PACKAGE: cannot send: " . $resolver->errorstring);
	return;
    }

    $net->set($handle, POLLIN, $self);
    return $self;
}

sub add_query ( $$ ) {
    my $self = shift;
    my $listener = shift;

    my $addr = $self->{addr};
    if ($addr) {
	&$listener($addr);
	return;
    }

    my $errorstring = $self->{errorstring};
    if ($errorstring) {
	$@ = $errorstring;
	&$listener;
	return;
    }

    my $listeners = $self->{listeners};
    push @$listeners, $listener;
}

sub __abort ( $$ ) {
    my $self = shift;
    my $errorstring = shift;

    my $listeners = $self->{listeners};
    while (my $listener = shift @$listeners) {
	$@ = $errorstring;
	&$listener;
    }

    $self->{errorstring} = $errorstring;
}

sub handle_event ( $$ ) {
    my $self = shift;
    my $handle = shift;
    my $type = shift;

    unless ($type & POLLIN) {
	my $net = $self->{net};
	$net->set($handle);
	close $handle;

	$self->__abort("$PACKAGE: timeout");
	return;
    }

    my $resolver = $self->{resolver};
    my $packet = $resolver->bgread($handle);

    my $net = $self->{net};
    $net->set($handle);
    close $handle;

    unless ($packet) {
	$self->__abort("$PACKAGE: cannot receive: " . $resolver->errorstring);
	return;
    }

    my @answer = $packet->answer;
    foreach my $rr (@answer) {
	$rr->type eq 'A' or next;

	my $addr = $rr->address;
	my $listeners = $self->{listeners};
	while (my $listener = shift @$listeners) {
	    &$listener($addr);
	}
	$self->{addr} = $addr;
	return;
    }

    $self->__abort("$PACKAGE: no address associated with hostname");
}

1;
