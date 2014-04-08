package Exception::API::HTTP;
use base qw(Exception::API);

sub new {
    my ($class, $response) = @_;

    my $self;
    if (ref($response) eq 'HTTP::Response') {
        $self = $class->SUPER::new($response->status_line);
        $self->{response} = $response;
    } else {
        $self = $class->SUPER::new($response);
    }

    return $self;
}

package QBit::Application::Model::API::HTTP;

use qbit;

use base qw(QBit::Application::Model::API);

use LWP::UserAgent;

sub init {
    my ($self) = @_;

    $self->SUPER::init();

    $self->{'__LWP__'} = LWP::UserAgent->new(timeout => $self->get_option('timeout', 300));
}

sub call {
    my ($self, $method, %params) = @_;

    my $uri = $self->get_option('url') . $method;
    my $delimiter = $uri =~ /\?/ ? '&' : '?';
    $uri .= $delimiter . join('&', map {$_ . '=' . uri_escape($params{$_})} keys %params) if %params;
    return $self->get($uri);
}

sub get {
    my ($self, $uri) = @_;

    my ($retries, $content, $response) = (0);

    while (($retries < $self->get_option('attempts', 3)) && !defined($content)) {
        sleep($self->get_option('delay', 1)) if $retries++;
        $response = $self->{'__LWP__'}->get($uri);

        if ($response->is_success()) {
            $content = $response->decoded_content();
            last;
        }
        if ($response->code == 408 && !$self->get_option('timeout_retry')) {
            last;
        }
    }

    $self->log(
        {
            url     => $uri,
            headers => $self->{'__LWP__'}->default_headers()->as_string(),
            status  => $response->code,
            content => defined($content) ? $content : undef,
            error   => defined($content) ? undef : $response->status_line,
        }
    ) if $self->can('log');

    throw Exception::API::HTTP $response unless defined($content);
    return $content;
}

TRUE;
