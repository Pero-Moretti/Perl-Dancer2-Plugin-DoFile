package Dancer2::Plugin::DoFile;
$Dancer2::Plugin::DoFile::VERSION = '0.0';
# ABSTRACT: File-based MVC plugin for Dancer2

use strict;
use warnings;

use Dancer2::Plugin;

use JSON;

has page_loc => (
    is      => 'rw',
    default => sub {'dofiles/pages'},
);

has default_file => (
    is      => 'rw',
    default => sub {'index'},
);

has extension_list => (
    is      => 'rw',
    default => sub { ['.do', '.view']}
);

plugin_keywords 'dofile';

sub BUILD {
    my $self     = shift;
    my $settings = $self->config;

    $settings->{$_} and $self->$_( $settings->{$_} )
      for qw/ page_loc default_file extension_list /;
}

sub dofile {
  my $plugin = shift;
  my $arg = shift;
  my %opts = @_;

  my $app = $plugin->app;
  my $settings = $app->settings;
  my $method = $app->request->method;
  my $pageroot = $settings->{appdir} . $plugin->page_loc;
  my $path = $arg || $app->request->path;

  # This is the specific file order we'll check

  # If any one of these returns content then we stop processing any more of them
  # Content is defined as an array ref (it's an Obj2HTML array), a hashref with a "content" element, or a scalar (assumed HTML string - it's not checked!)
  # This can lead to some interesting results if someone doesn't explicitly return undef when they want to fall through to the next file
  # as perl will return the last evaluated value, which would be intepretted as content according to the above rules

  # Safety first...
  $path =~ s|/$|"/".$plugin->default_file|e;
  $path =~ s|^/+||;
  $path =~ s|\.\./||g;
  $path =~ s|~||g;

  if (!$path) { $path = $plugin->default_file; }
  if (-d $pageroot."/$path") { $path .= "/".$plugin->default_file; }

  $plugin->app->log( info => "DoFile looking for $path\n");

  my $successful = 0;

  foreach my $ext (@{$plugin->extension_list}) {
    foreach my $m ("", "-$method") {
      my $cururl = $path;
      my @path = ();

      # This iterates back through the path to find the closest FILE downstream, using the rest of the url as a "path" argument
      while (!-f $pageroot."/".$cururl.$m.$ext && $cururl =~ s/\/([^\/]*)$//) {
        if ($1) { unshift(@path, $1); }
      }

      # To do - look for appropriate js files to include

      # "Do" the file
      if ($cururl && -f $pageroot."/".$cururl.$m.$ext) {
        our $args = { path => \@path, thisurl => $cururl, dofileplugin => $plugin };
        my $result = do($pageroot."/".$cururl.$m.$ext);
        if ($@ || $!) { $plugin->app->log( error => "Error processing $pageroot / $cururl.$m.$ext: $@ $!\n"); }
        if (defined $result && ref $result eq "HASH") {
          if (defined $result->{url} && !defined $result->{redirect}) {
              $path = $result->{url};
              next OUTER;
          }
          if (defined $result->{content}) {
            return $result;
          }
          # Move on to the next file

        } elsif (ref $result eq "ARRAY") {
          return { content => $result };

        } elsif (!ref $result && $result) {
          # do we assume this is HTML? Or a file to use in templating? Who knows!
          return { content => $result };

        }
      }
    }
  }

  # If we got here we didn't find a do file that returned some content
  return { status => 404 };
}

sub view_pathname {
  my ( $self, $view ) = @_;
  return path($view);
}
sub layout_pathname {
  my ( $self, $layout ) = @_;
  return $layout;
}

1;

__END__

=pod

=head1 NAME

Dancer2::Plugin::DoFile

=head1 SYNOPSYS

In your config.yml

    plugins:
      DoFile:
        page_loc: "dofiles/pages"
        default_file: "index"
        extension_list: ['.do','.view']

Make sure you have created the directory used for page_loc

Within a route in dancer2:

    my $result = dofile 'path/to/file'

You must not include the extension of the file as part of the path, as this will
be added per the settings.

Or a default route:

    any qr{.*} => sub {
      my $self = shift;

      my $result = dofile undef;

    };

When the 1st parameter to 'dofile' is undef; it'll use the URI to work out what
the file(s) to execute are.

=head1 DESCRIPTION

DoFile is a way of automatically pulling multiple perl files to execute as a way
to simplify routing complexity in Dancer2 for very large applications. In
particular it was designed to offload "as many as possible" URIs that related to
some standard functionality through a default route, just by having files
existing for the specific URI.

Unlike standard web servers though, DoFile actually takes a more MVC approach.
The magic will look through your filesystem for files to 'do' (execute), and
there may be several. The intent is to split out controller files (.do) and
view files (.view), and these may individually be rolled out or split out.

=head2 File Search Ordering

When presented with the URI C<path/to/file> DoFile will begin searching for
files that can be executed for this request, until it finds one that returns
something that looks like content, when it stops.

=over 4

=item * By extension

The default extensions .do and .view are checked, unless defined in your
config.yml. The intention here is that .do files contain controller code and
don't typically return content, but may return redirects. After .do files have
been executed, .view files are executed. These are expected to return content.

=item * Root and by HTTP request method

For each extension, first the "root" file is tested, then a file that matches
C<file-METHOD.ext> is tested (where METHOD is the HTTP request method for this
request, .ext is the extension).

=item * If neither is found, iterating up the directory tree

If your call to C<path/to/file> results in a miss for C<path/to/file.do>, DoFile
will then test for C<path/to.do> and finally C<path.do> before moving on to
C<path/to/file-METHOD.do>

Once DoFile has found one it will not transcend the directory tree any further.
Therefore defining C<path/to/file.do> and C<path/to.do> will not result in
both being executed for the URI C<path/to/file> - only the first will be
executed.

=back

If you define files like so:

    path.do
    path/
      to.view
      to/
        file-POST.do

A POST to the URI C<path/to/file> will execute C<path.do>, then
C<path/to/file-POST.do> and finally C<path/to.view>.

=head2 What the router sees

What the router should expect back from DoFile is a hashref, even if the files
being executed do not return a hashref. This hashref may have:

=over 4

=item * A C<contents> element

The implication is that you've had the web page to be served back. Note that
DoFile doesn't care if this is a scalar string or an arrayref. This Plugin
was designed to work with Obj2HTML, so in the case of an arrayref the
implication is that Obj2HTML should be asked to convert that to HTML.

=item * A C<url> and a C<redirect> element

In this case the router should send a 30x response redirecting the client.

=back

DoFile may also return other elements meaningful to your router code, for
example C<status> is returned (as 404) in the event that DoFile didn't find any
files to execute.

=head2 Return values of the executed files by DoFile

The result (returned value) of each file is checked; if something is returned
DoFile will inspect the value to determine what to do next.

=head3 Internal Redirects

If a hashref is returned it's checked for a C<url> element but NO C<redirect>
element. In this case, the DoFile restarts from the begining using the new URL.
This is a method for internally redirecting. For example, returning:

    {
      url => "account/login"
    }

Will cause DoFile to start over with the new URI C<account/login>, without
processing any more files from the old URI

=head3 Content

If a scalar or arrayref is returned, it's wrapped into a hashref into the
C<contents> element and sent back to the router.

If a hashref is returned and contains a C<contents> element, or both a url and
redirect element, no more files will be processed. The entire hashref is
returned to the router.

=head1 AUTHOR

Pero Moretti

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2022 by Pero Moretti.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.
