package AnyEvent::WebSocket::Socket;

# 2014, EyeSyt LLC. All rights reserved.
#

use JSON::XS qw(encode_json decode_json);
use Protocol::WebSocket::Frame;

use strict;
use warnings;

sub new {
	my $class = shift;
	my $handle = shift;
	my $options = shift;
	my $self = {};
	$self = { %{$options} } if $options;
	$self->{ws_handle} = $handle;
	$self->{ws_frame} = Protocol::WebSocket::Frame->new;
	bless $self,$class;
	return $self;
}

sub send {
	my $self = shift;
	my $input = shift;
	my $message = $input;
	$message = encode_json($input) if ( ref($input) eq 'ARRAY' || ref($input) eq 'HASH' );
	print STDERR "WS Response: $message\n";
	$self->{ws_handle}->push_write($self->{ws_frame}->new($message)->to_bytes);
}
sub encode {
	my $self = shift;
	my $input = shift;
	my $message = $input;
	$message = encode_json($input) if ( ref($input) eq 'ARRAY' || ref($input) eq 'HASH' );
	return $message;
}
sub handle {
	my $self = shift;
	return $self->{ws_handle};
}
sub disconnect {
	my $self = shift;
	$self->{ws_handle}->push_shutdown();
	$self->{ws_handle}->destroy();
	undef $self->{ws_handle};
	undef $self->{ws_frame};
	undef $self;
}

1;
