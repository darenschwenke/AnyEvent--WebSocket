package AnyEvent::WebSocket;

# 2014, EyeSyt LLC. All rights reserved.
#

use File::Basename;
use File::MimeInfo;

use HTTP::Parser::XS qw(parse_http_request);
use utf8;
use Data::Dumper;
use AnyEvent;
use FindBin;
use lib "$FindBin::Bin/../../lib/"; 
use AnyEvent::Socket qw( tcp_server ); 
use AnyEvent::WebSocket::Socket;
use AnyEvent::WebSocket::HTTPD;
use JSON::XS qw(decode_json);

BEGIN { AnyEvent::common_sense }

use base 'Exporter';

our @EXPORT = qw(
  	ws_server 
);
our $VERSION = '0.0.1';
our $CONNECTIONS;
our $TIMEOUTS;

sub ws_server($$$$;$) {
	my ($host, $service, $new_ws_handler, $http_handler,$options) = @_;
	print STDERR "Started Server $host: $service\n";
	my $server = tcp_server $host, $service, sub {
		my ($sock, $host, $port) = @_;
		print STDERR "Accept $host: $port\n";
		my ($ws_handshake,$buffer);
		my $ws_handler;
		my $ws_frame = Protocol::WebSocket::Frame->new;
		my $connId =  fileno($sock);
		my $CONNECTIONS->{$connId} = AnyEvent::Handle->new(fh => $sock, %{$options});
		my $disconnect = sub {
			my $reason = shift;
			$ws_handler->disconnect($reason) if $ws_handler && $ws_handler->can('disconnect') && $ws_handshake->is_done;
			if ( $CONNECTIONS->{$connId} ) {
				$CONNECTIONS->{$connId}->push_shutdown();
				$CONNECTIONS->{$connId}->destroy();
				undef $CONNECTIONS->{$connId};	
			}
			undef $ws_handler;
			undef $TIMEOUTS->{$connId};
			undef $sock;
			undef $buffer;
		};
		$CONNECTIONS->{$connId}->on_error( sub {
			my $error = $_[2];
			$disconnect->($error);
		});
		$CONNECTIONS->{$connId}->on_timeout( sub {
			$disconnect->('Timed out');
		});
		$CONNECTIONS->{$connId}->on_eof( sub { 
			my $error = $_[2];
			$disconnect->($error);
		});
		$CONNECTIONS->{$connId}->on_read( sub {
			my $socket_handle = shift;
			my $chunk = $socket_handle->{rbuf};
			$socket_handle->{rbuf} = undef;
			if ( ! $ws_handshake ) {
				$buffer .= $chunk;
				my $request = {};
				my $ret = parse_http_request($buffer,$request);
				if ($ret == -2) {
					#  header stalled?
				} elsif ($ret == -1) {
  					$socket_handle->push_write($http_handler->on_error('400 BAD REQUEST'));
					$disconnect->('Bad request');
  				} elsif ( ! $ws_handshake && ( uc($request->{HTTP_CONNECTION}) eq 'UPGRADE' || uc($request->{UPGRADE}) eq 'WEBSOCKET' ) ) {
					$ws_handler = $new_ws_handler->($socket_handle) if ( ! $ws_handler ); # create handler.
					$ws_handshake = Protocol::WebSocket::Handshake::Server->new;
					$ws_frame = Protocol::WebSocket::Frame->new;
  					if (!$ws_handshake->is_done) {
						$ws_handshake->parse($buffer);
						if ($ws_handshake->is_done) {
							$socket_handle->push_write($ws_handshake->to_string);
							$ws_handler->can('on_open')->($ws_handler) if $ws_handler->can('on_open');
							return;
						}
  					}
  				} else {
  					$request->{reply} = sub { $socket_handle->push_write(shift) };
  					if ( $request->{REQUEST_METHOD} eq 'GET' && $http_handler->can('on_get') ) {
						$http_handler->can('on_get')->($http_handler,$request);
  					} elsif ( $request->{REQUEST_METHOD} eq 'POST' && $http_handler->can('on_post') ) {
						$http_handler->can('on_post')->($http_handler,$request);
  					} elsif ( $request->{REQUEST_METHOD} eq 'HEAD' && $http_handler->can('on_head') ) {
						$http_handler->can('on_head')->($http_handler,$request);
  					} elsif ( $http_handler->can('on_other') ) {
						$http_handler->can('on_other')->($http_handler,$request);
  					} else {
  						$socket_handle->push_write($http_handler->method_error(501, 'NOT IMPLEMENTED'));
	  					$disconnect->('Not Implemented');
	  					return;
  					}
  					$disconnect->('');
  					return;
  				}
			} elsif ( $ws_handshake ) {
				if ( $ws_frame->is_close ) {
					$ws_handler->can('on_close')->($ws_handler) if $ws_handler->can('on_close');
					$disconnect->('Recieved close frame.');
				} elsif ( $ws_frame->is_ping ) {
					$ws_handler->can('on_ping')->($ws_handler) if $ws_handler->can('on_ping');
				} elsif ( $ws_frame->is_pong ) {
					$ws_handler->can('on_pong')->($ws_handler) if $ws_handler->can('on_pong');
				} elsif ( $ws_frame->is_text ) {
					$ws_frame->append($chunk);
					while (my $raw_text = $ws_frame->next ) {
						my $input = decode_json($raw_text);
						print STDERR "WS Request: " . Dumper($input);
						if ( $ws_handler->can('on_message') ) {
							$ws_handler->can('on_message')->($ws_handler,$input);
						} else { 
							$input->{type} ||= '';
							$ws_handler->can($input->{type})->($ws_handler,$input) if $input->{type} && $ws_handler->can($input->{type});
						}
					}
				} elsif ( $ws_frame->is_binary ) {
					$ws_handler->can('on_binary')->($ws_handler,$ws_frame->next) if $ws_handler->can('on_binary');
				}
			}
		});
	};
};

1;
