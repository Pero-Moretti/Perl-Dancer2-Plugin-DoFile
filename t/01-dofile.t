use strict;

use File::Basename;
use Path::Tiny;
use FindBin qw( $Bin );
use HTTP::Request::Common;
use JSON::MaybeXS;
use Module::Load;
use Plack::Test;
use Test::More;
use Test::Mock::LWP::Dispatch;
use URI;

# setup dancer app
{
  package App;
  use Dancer2;
  use Dancer2::Plugin::DoFile;

  prefix '/';
  any qr{.*} => sub {
    my $self = shift;
#    print STDERR "--> Request received for ".$self->request->path."\n";
    my $result = dofile undef;
    if ($result && ref $result eq "HASH") {
      if (defined $result->{status}) {
#        print STDERR "----> Updating status to $result->{status}\n";
        status $result->{status};
      }
      if (defined $result->{url}) {
#        print STDERR "----> Redirecting to $result->{url}\n";
        if (defined $result->{forward}) {
          return forward $result->{url};
        } else {
          return redirect $result->{url};
        }
      } elsif (defined $result->{content}) {
#        print STDERR "----> Have found content!\n";
        return $result->{content};
      }
    }
  };
  true;
}

# setup plack
my $app = App->psgi_app;
is( ref $app, 'CODE', 'Got app' );

# ok( $res->is_success, '[GET /] successful' );

test_psgi
    app    => $app,
    client => sub {
        my $cb  = shift;

        my $res = $cb->(GET "/");
        is($res->code, 200, "[Basic test] Response code (200)");
        is($res->content, "index page success", "[Basic test] Contents of the index page");

        my $res = $cb->(GET "/page-not-found");
        is($res->code, 404, "[Page not found] Response code (404)");

        my $res = $cb->(GET "/redirect");
        is($res->code, 302, "[Client Redirect] Response code (302)");

        my $res = $cb->(GET "/internal-redirect");
        is($res->code, 200, "[Internal Reidrect] Response code (200)");
        is($res->content, "Internal Redirect OK!", "[Internal Redirect] Contents of the resultant page");

        my $res = $cb->(GET "/internal-forward");
        is($res->code, 200, "[Internal Forward] Response code (200)");
        is($res->content, "Internal Forward OK!", "[Internal Redirect] Contents of the resultant page");

        # path to file test interating through various extensions and directories.
        # First path.do is executed; this sets stash->{first} = 1
        # Second path/to/file-POST.do is executed; this sets stash->{second} = 2
        # Third path/to.view is executed; this sets stash->{third} = 3
        # Last path-POST.view is executed; this checks the previous and returns "First Second Third Fourth"
        # They can't run out of order; there's checking for that too!
        my $res = $cb->(POST "/path/to/file");
        is($res->code, 200, "[/path/to/file] Response code (200)");
        is($res->content, "First Second Third Fourth", "[/path/to/file] Contents of the resultant page");


#
#        my $got_uri = URI->new($res->header('Location'));
#        for ( qw(scheme host path) ) {
#            ok($got_uri->$_ eq $wanted_uri->$_, "[$provider] Redirect URL ($_)");
#        }
#
#        is_deeply( +{ $got_uri->query_form }, +{ $wanted_uri->query_form }, "[$provider] Redirect URL (query)" );

    };

# all done!
done_testing;
