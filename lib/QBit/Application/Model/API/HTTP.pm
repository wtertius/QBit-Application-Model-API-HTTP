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

my %SPECIAL_FIELDS_NAMES = (
    ''      => TRUE,
    ':post' => TRUE,
);

sub init {
    my ($self) = @_;

    $self->SUPER::init();

    $self->{'__LWP__'} = LWP::UserAgent->new(timeout => $self->get_option('timeout', 300));
}

sub call {
    my ($self, $method, %params) = @_;

    my $uri = $self->get_option('url') . $method;

    my @request_fields = grep {!exists($SPECIAL_FIELDS_NAMES{$_})} keys(%params);

    if (exists($params{':post'})) {
        $params{''} = {hash_transform(\%params, \@request_fields)} if !exists($params{''}) && @request_fields;
    } elsif (@request_fields) {
        my $delimiter = $uri =~ /\?/ ? '&' : '?';
        $uri .= $delimiter . join('&', map {$_ . '=' . uri_escape($params{$_})} @request_fields);
    }

    return $self->get($uri, %params);
}

sub get {
    my ($self, $uri, %params) = @_;

    my ($retries, $content, $response) = (0);

    while (($retries < $self->get_option('attempts', 3)) && !defined($content)) {
        sleep($self->get_option('delay', 1)) if $retries++;

        if (exists($params{':post'})) {
            $response = $self->{'__LWP__'}->post($uri, Content => $params{''});
        } else {
            $response = $self->{'__LWP__'}->get($uri);
        }

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
            request  => $response->request->as_string,
            url      => $uri,
            status   => $response->code,
            response => $response->headers->as_string,
            (defined($content) ? (content => $content) : (error => $response->status_line)),
        }
    ) if $self->can('log');

    throw Exception::API::HTTP $response unless defined($content);
    return $content;
}

TRUE;
