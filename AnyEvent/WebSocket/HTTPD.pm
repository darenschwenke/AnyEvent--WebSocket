  							
package AnyEvent::WebSocket::HTTPD;

# 2014, EyeSyt LLC. All rights reserved.
#

use File::Basename;
use File::MimeInfo;
use HTTP::Headers;
use HTTP::Response;
use HTTP::Date;
use Data::Dumper;

use Cwd qw(realpath);
use File::Spec qw( rel2abs );
use URI::Escape qw( uri_unescape );
use AnyEvent::InMemoryCache;

our $SERVER_NAME = 'AnyEvent::WebSocket::HTTPD';
our $HTTP_CACHE;
our $EXPIRE = 5;

sub enable_cache {
	my $self = shift;
	my $expire_sec = shift || 300;
	return;
	$HTTP_CACHE = AnyEvent::InMemoryCache->new(expires_in => $expire_sec);
}

sub new {
	my $class = shift;
	my $options = shift;
	my $self = {};
	$self = { %{$options} } if $options;
	bless $self,$class;
	$self->enable_cache($self->{cache} ) if $self->{cache};
	die('Webroot "' . $self->{web_root} . '" does not exist') if ( ! -d $self->{web_root} );
	return $self;
}

sub on_error {
	my $self = shift;
	my $code = shift || 400;
	my $message = shift || 'BAD REQUEST';
	my $http_date = time2str();
	return 'HTTP/1.1 ' . $code . ' ' . $error . '
Date: ' . $http_date . '
Server: ' . $SERVER_NAME . '
Content-Length: ' . length($message) . '
Last-Modified: '. $http_date . '
Expires: '. $http_date . "\r\n\r\n" . $message;
}

sub on_get {
	my $self = shift;
	my $request = shift;
	my $raw_path = uri_unescape($request->{PATH_INFO});
	my $http_date = time2str();
	my $filename = $self->{web_root} . $raw_path;
	if ( -d $filename && -e $filename . 'index.html' ) {
		$filename .= 'index.html';
	}
	my $full_path = $filename; #rel2abs($filename,$self->{web_root});
	if ( 0 || $HTTP_CACHE ) {
		my $cached = $HTTP_CACHE->get($filename);
		if ( $cached ) {
			$request->{reply}->($cached);
			return;
		}
	}
	if ( -r $filename ) {
		if ($filename =~ /jquery\.onload\.js/i ) {
			my $content;
			my $ws_host = $request->{HTTP_HOST};
			my $size = -s $filename or $! and return warn "Can't read file `$filename': $!";
			open my $f, '<:raw',$filename or return  warn "Can't open file `$filename': $!";
			while ($size > 0) {
				my $l = sysread($f,my $buf,4096);
				defined $l or last;	
				$size -= $l;
				$content .= $buf;
			}
			$content =~ s/__WS_HOST__/$ws_host/g;
			$size = length($content);
			my $header = HTTP::Headers->new(
				Server 			=> $SERVER_NAME,
				Accept_Ranges	=> 'bytes',
				Date 			=> $http_date,
				Content_Type 	=> mimetype($filename),
				Last_Modified 	=> $http_date,
				Content_Length 	=> $size,
				Cache_Control 	=> 'max-age=' . $EXPIRE,	
			);
			my $response = HTTP::Response->new( 200, $request->{SERVER_PROTOCOL} , $header );
			$request->{reply}->($response->as_string . $content);
			print STDERR "HTTP Request: " . $raw_path . "\n" . $response->as_string;
			$HTTP_CACHE->set($filename,$response->as_string . $content) if $HTTP_CACHE;
		} else {
			my $size = -s $filename or $! and return warn "Can't stat `$filename': $!";
			my $start_byte = 0;
			my $code = 200;
			my $end_byte = $size;
			my $ranged = 0;
			if ( $request->{RANGE} && $request->{RANGE} =~ /bytes=(\d*)-(.*)$/ ) {
				$start_byte = $1;
				$end_byte = $2 || $size;
				$code = 206;
				$ranged = 1;
			}
			my $header = HTTP::Headers->new(
				Server 			=> $SERVER_NAME,
				Accept_Ranges	=> 'bytes',
				Date 			=> $http_date,
				Content_Type 	=> mimetype($filename),
				Last_Modified 	=> $http_date,
				Content_Length 	=> ( $end_byte - $start_byte ),
				Cache_Control 	=> 'max-age=' . $EXPIRE,	
			);
			if ( $ranged ) {
				$header->push_header(Content_Range => 'bytes ' . $start_byte . '-' . $end_byte . '/' . $size);
			}
			my $response = HTTP::Response->new( $code, $request->{SERVER_PROTOCOL}  , $header);
			my $cache = '';
			$request->{reply}->($response->as_string);
			$cache .= $response->as_string if ! $ranged && $HTTP_CACHE;
			open my $f, '<:raw',$filename or return  warn "Can't open file `$filename': $!";
			if ( $start_byte ) {
				sysseek ( $f,$start_byte,0);
				$size -= $start_byte;
			}
			while ($size > 0 ) {
				my $l = sysread($f,my $buf,4096);
				defined $l or last;
				$size -= $l;
				$request->{reply}->($buf);
				$cache .= $buf if ! $ranged && $HTTP_CACHE;
			}
			$HTTP_CACHE->set($filename,$cache) if ! $ranged && $HTTP_CACHE; 
			print STDERR "HTTP Request: " . $raw_path . "\n" . $response->as_string;
		}
	} else {
		my $error = $self->on_error(404, 'Not found');
		print STDERR "HTTP Request: " . $raw_path . "\n" . $error;
		$request->{reply}->($error);
	}
}
1;