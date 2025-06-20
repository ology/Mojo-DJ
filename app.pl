#!/usr/bin/env perl
use Mojolicious::Lite -signatures;

use Capture::Tiny qw(capture_stdout);
use Crypt::Passphrase ();
use Crypt::Passphrase::Argon2 ();
use Encoding::FixLatin qw(fix_latin);
use Mojo::SQLite ();
# use Mojo::File ();
use WebService::YTSearch ();

helper fix_latin => sub ($c, $string) { # for use in the template
  return fix_latin($string);
};

helper sql => sub ($c) {
  return state $sql = Mojo::SQLite->new('sqlite:app.db');
};

helper auth => sub ($c) {
  my $user = $c->param('username');
  my $pass = $c->param('password');
  return 0 unless $user && $pass;
  my $sql = 'select id, name, password from account where name = ? and active = 1';
  my $record = $c->sql->db->query($sql, $user)->hash;
  my $password = $record ? $record->{password} : undef;
  my $authenticator = Crypt::Passphrase->new(encoder => 'Argon2');
  if (!$authenticator->verify_password($pass, $password)) {
    return 0;
  }
  $c->session(auth => 1);
  $c->session(user => $record->{name});
  $c->session(user_id => $record->{id});
  return 1;
};

get '/' => sub { shift->redirect_to('login') } => 'index';

get '/login' => sub { shift->render } => 'login';

post '/login' => sub ($c) {
  if ($c->auth) {
    return $c->redirect_to('app');
  }
  $c->flash('error' => 'Invalid login');
  $c->redirect_to('login');
} => 'auth';

get '/logout' => sub ($c) {
  delete $c->session->{auth};
  delete $c->session->{user};
  delete $c->session->{user_id};
  $c->session(expires => 1);
  $c->redirect_to('login');
} => 'logout';

under sub ($c) {
  return 1 if ($c->session('auth') // '') eq '1';
  $c->redirect_to('login');
  return undef;
};

get '/app' => sub ($c) {
  my $action = $c->param('action') || ''; # user action like 'interp'
  my $song   = $c->param('song')   || ''; # song title
  my $artist = $c->param('artist') || ''; # artist or band

  my $user_id = $c->session('user_id');
  my $sql = Mojo::SQLite->new('sqlite:app.db');

  my $interpretation = ''; # AI interpretations

  if ($action eq 'interp' && $song) {
    my $seek = $song;
    $seek .= " by $artist" if $artist;
    # my $file = Mojo::File->new('./prompt.txt');
    # my $instruction = $file->spew;
    my $instruction = <<'INSTRUCTION';
You are a knowledgeable musical scholar and historian, your passion is to uncover the deep stories behind music tracks.

For the song [Song Title] by [Artist], tell me about its story. Each segment must start with an interesting fact (do not lead with a question), followed by interesting aspects of the song. But do not label your response with the topic names.

Topics are:

 * The Roots: Where did this song come from, both musically and culturally? What are its influences, and what traditions does it draw upon?
 * The Story of the Artist: What was going on in the artist's life when they wrote or recorded this song? How does it fit into their personal and creative journey?
 * The Cultural Landscape: What was happening in the wider world when this song was released? How did it reflect or influence the social and historical moment?
 * The Musical DNA: Break down the musical elements of the song. What makes it unique, and what do those choices tell us?
 * The Legacy: How has this song's meaning and impact evolved over time? Where do we see its influence?

Create a detailed, factual outline. Your tone should be knowledgeable, engaging, and accessible for a general audience. Use accessible language without getting folksy. Avoid stereotypical communication styles, but don’t get too academic.

Absolutely never use dialectical narrative structures. No thesis-antithesis-synthesis, no "it's not just x, it's also y." Avoid staccato sentences. Do not use paragraph headers.

YOU MUST NOT GENERATE INFORMATION THAT IS NOT SUPPORTED BY VERIFIABLE SOURCES. Any invention or speculation is a fundamental failure. Your sourcing strategy must adapt to the artist's profile to ensure the highest level of accuracy.

For major commercial artists, your information must be drawn from official and reputable sources. These include, but are not limited to: official artist or record label websites, digital and physical album liner notes, published interviews in established music publications (such as Rolling Stone, Billboard, Pitchfork), and official biographies or documentaries.

For independent or less well-known artists, you must prioritize information found on their direct-to-fan platforms and official channels. These sources include, but are not limited to: Spotify, YouTube, Bandcamp, SoundCloud, DistroKid, CD Baby, TuneCore, Apple Music, TikTok, and Patreon.

The most important thing is that made-up, fake, or hallucinated information must not be included. If, after checking the appropriate sources for any artist, verifiable information cannot be found, it is imperative that no false information is included in the response. You must instead state the Artist,and track name.

Do not confuse a song title with an album title. Often a song on an album will have the same title as the album. Double-check that your story is about the song itself.

As a factual assistant, follow this pipeline automatically:

 * Abstraction: Internally outline high-level aspects of the question.
 * Initial Draft: Produce a direct preliminary answer.
 * Verification Planning: Formulate 2–3 internal fact-check questions about key statements.
 * Evidence Checking: Answer each verification question independently, not referencing the draft.
 * Final Assembly: Based on your verification, build a concise final answer.
 * Deliver: Emit only the final answer.
INSTRUCTION
    $interpretation = _interpret($instruction, $seek);
    $interpretation .= "\n<p></p><ul>";
    my $yt = WebService::YTSearch->new(key => $ENV{YOUTUBE_API_KEY});
    my %query = (q => $seek, type => 'video', maxResults => 1);
    my $r = $yt->search(%query);
    for my $result ($r->{items}->@*) {
      my $url = 'https://www.youtube.com/watch?v=' . $result->{id}{videoId};
      my $title = $result->{snippet}{title};
      $interpretation .= qq|\n\n<li><a href="$url" target="_blank" rel="noopener noreferrer">$title<\/a><\/li>|;
    }
    $interpretation .= "\n</ul>";
  }

  $c->render(
    template => 'app',
    can_chat => $ENV{GEMINI_API_KEY} ? 1 : 0,
    interp   => $interpretation,
    song     => $song,
    artist   => $artist,
  );
} => 'app';

sub _interpret ($instruction, $seeking) {
  my $response = _get_response('user', $instruction, $seeking);
  $response =~ s/\*\*//g;
  $response =~ s/##+//g;
  $response =~ s/\n+/<p><\/p>/g;
  return $response;
}

sub _get_response ($role, $instruction, $prompt) {
  return unless $prompt;
  my @cmd = (qw(python3 chat.py), $instruction, $prompt);
  my $stdout = capture_stdout { system @cmd };
  chomp $stdout;
  return $stdout;
}

app->start;

__DATA__

@@ login.html.ep
% layout 'default';
% title 'Login';
<p></p>
<form action="<%= url_for('auth') %>" method="post">
  <input class="form-control" type="text" name="username" placeholder="Username (min=3, max=20)">
  <br>
  <input class="form-control" type="password" name="password" placeholder="Password (min=10, max=20)">
  <br>
  <input class="form-control btn btn-primary" type="submit" name="submit" value="Login">
</form>

@@ app.html.ep
% layout 'default';
% title 'AI Music Scholar';
<p></p>
% # Interpret
%   if ($can_chat) {
  <form method="get">
    <input type="text" class="form-control" name="song" placeholder="Song title" value="<%= $song %>">
    <p></p>
    <input type="text" class="form-control" name="artist" placeholder="Artist or band" value="<%= $artist %>">
    <p></p>
    <button type="submit" name="action" title="Submit this song for analysis" value="interp" class="btn btn-primary" id="interp">
      Submit</button>
  </form>
  <p></p>
%   }
<p></p>
% # Response
% if ($interp) {
    <hr>
    <%== fix_latin($interp) %>
<!--    <p></p>
    Transcript:<br><audio controls><source type="audio/wav" src="/out.wav"></audio>
-->
% }

@@ layouts/default.html.ep
<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <link rel="icon" type="image/png" href="/favicon.ico">
    <link href="/css/bootstrap.min.css" rel="stylesheet" integrity="sha384-EVSTQN3/azprG1Anm3QDgpJLIm9Nao0Yz1ztcQTwFspd3yD65VohhpuuCOmLASjC" crossorigin="anonymous">
    <script src="/js/jquery.min.js"></script>
    <script src="/js/bootstrap.min.js" integrity="sha384-cVKIPhGWiC2Al4u+LWgxfKTRIcfu0JTxR+EQDz/bgldoEyl4H0zUF0QKbrJ0EcQF" crossorigin="anonymous"></script>
    <link rel="stylesheet" href="/css/style.css">
    <title><%= title %></title>
    <script>
    $(document).ready(function() {
      $("#interp").click(function() {
        $('#loading').show();
      });
    });
    $(window).on('load', function() {
        $('#loading').hide();
    })
    </script>
  </head>
  <body>
    <div id="loading">
      <img id="loading-image" src="/loading.gif" alt="Loading..." />
    </div>
    <div class="container padpage">
% if (flash('error')) {
      <h2 style="color:red"><%= flash('error') %></h2>
% }
      <h3><img src="/favicon.ico"> <a href="<%= url_for('app') %>"><%= title %></a></h3>
      <%= content %>
      <p></p>
      <div id="footer" class="small">
        <hr>
        <a href="<%= url_for('logout') %>">Logout</a>
      </div>
      <p></p>
    </div>
  </body>
</html>
