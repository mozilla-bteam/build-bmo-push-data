#!/usr/bin/perl
use strict;
use warnings;
use autodie;

# steps for pushing a bmo update
# 1. execute this script, which
#    - updates the repository
#    - determines changes on the master branch but not on production
# 2. use the first url and text to create a push bug
# 3. merge from master --> production
#    - cd /opt/bugzilla/repo/bmo/master
#    - git checkout production
#    - git merge master  # accept the default commit message
#    - git push
#    - git checkout master
# 4. wait for someone to take the bug and follow the push steps in mana
# 5. create a blog post (paste into the "text" tab)
# 6. send an email to tools.bmo
# 7. update the WeeklyUpdates wiki page with selected and edited descriptions
#    (only include changes that are relevant to all/most of the community)
# 8. edit the RecentChanges wiki (add today's push to the top, delete the oldest)
# 9. edit the relevant month's wiki page (add today's push to the top)
# 10. set the bugzilla-version param to today's date (yyyy.mm.dd)

use lib '/opt/bmo-admin-scripts/lib';
use Bz;
use DateTime;
use IPC::System::Simple qw(runx capture);

chdir('/opt/bugzilla/repo/bmo/master');
info("updating repo");
runx(qw(git pull));
my $date = DateTime->now->set_time_zone('PST8PDT')->ymd('');
my $tag = "https://github.com/mozilla-bteam/bmo/tree/release-$date.1";

# override detected prod head revision as param 1
my $production_rev;
$production_rev = shift if @ARGV && $ARGV[0] !~ /.=./;
if (!$production_rev) {
    chdir('/opt/bugzilla/repo/bmo/production');
    runx(qw(git pull));
    $production_rev = capture(qw(git log -1 --pretty=format:%H));
    chdir('/opt/bugzilla/repo/bmo/master');
}
my $master_rev = capture(qw(git log -1 --pretty=format:%H));
print "$production_rev -> $master_rev\n";

# you can also pass in rev=bug as additional params to assign bug numbers to
# commits that don't have it in the comment message.
# eg. c0d00a5=1118365
#     maps commit c0d00a5 to bug 1118365
my %rev_bug_map;
while (my $arg = shift) {
    next unless $arg =~ /^([^=]+)=(\d+)/;
    $rev_bug_map{$1} = $2;
}

my @log = capture(qw(git log --oneline), "$production_rev..$master_rev");
die "nothing to commit\n" unless @log;
chomp(@log);

my @revisions;
foreach my $line (@log) {
    print "$line\n";
    unless ($line =~ /^(\S+) (.+)$/) {
        alert("skipping $line");
        next;
    }
    my ($revision, $message) = ($1, $2);

    my @bug_ids;
    if (exists $rev_bug_map{$revision}) {
        info("mapping '$line' to bug $rev_bug_map{$revision}");
        push @bug_ids, $rev_bug_map{$revision};
    } elsif ($message =~ /\bBug (\d+)/i) {
        if ($1 == 375950) {
            push @bug_ids, 1375950;
        } else {
            push @bug_ids, $1;
        }
    }

    if (!@bug_ids) {
        alert("skipping $line (no bug)");
        next;
    }

    foreach my $bug_id (@bug_ids) {
        my $duplicate = 0;
        foreach my $revisions (@revisions) {
            if ($revisions->{bug_id} == $bug_id) {
                $duplicate = 1;
                last;
            }
        }
        next if $duplicate;

        info("loading bug $bug_id");
        my $bug = Bz->bugzilla->bug($bug_id);
        if ($bug->{status} eq 'RESOLVED' && $bug->{resolution} ne 'FIXED') {
            alert("skipping bug $bug_id " . $bug->{summary} . " RESOLVED/" . $bug->{resolution});
            next;
        }
        if ($bug->{summary} =~ /\bbackport\s+(?:upstream\s+)?bug\s+(\d+)/i) {
            my $upstream = $1;
            info("loading upstream bug $upstream");
            $bug->{summary} = Bz->bugzilla->bug($upstream)->{summary};
        }
        unshift @revisions, {
            hash    => $revision,
            bug_id  => $bug_id,
            summary => $bug->{summary},
        };
    }
}
if (!@revisions) {
    die "no new revisions.  make sure you run this script before production is updated.\n";
}

my $first_revision = $revisions[0]->{hash};
my $last_revision  = $revisions[$#revisions]->{hash};

# push bug

print "\n";
print "https://bugzilla.mozilla.org/enter_bug.cgi?product=bugzilla.mozilla.org&component=Infrastructure&short_desc=push+updated+bugzilla.mozilla.org+live\n";
print "revisions: $first_revision - $last_revision\n";
foreach my $revision (@revisions) {
    print "bug $revision->{bug_id} : $revision->{summary}\n";
}
print "\n\n";

# blog post

print "https://globau.wordpress.com/wp-admin/post-new.php\n";
print "[release tag]($tag)\n\n";
print "the following changes have been pushed to bugzilla.mozilla.org:\n<ul>\n";
foreach my $revision (@revisions) {
    printf '<li>[<a href="https://bugzilla.mozilla.org/show_bug.cgi?id=%s" target="_blank">%s</a>] %s</li>%s',
        $revision->{bug_id}, $revision->{bug_id}, html_escape($revision->{summary}), "\n";
}
print "</ul>\n";
print qq#discuss these changes on <a href="https://lists.mozilla.org/listinfo/tools-bmo" target="_blank">mozilla.tools.bmo</a>.\n#;
print "\n\n";

# tools.bmo email

print "the following changes have been pushed to bugzilla.mozilla.org:\n\n";
print "(tag: $tag)\n";
foreach my $revision (@revisions) {
    printf "https://bugzil.la/%s : %s\n", $revision->{bug_id}, $revision->{summary};
}
print "\n\n";

# recent changes wiki

print "https://wiki.mozilla.org/BMO/Recent_Changes\n";
print "== " . DateTime->now->set_time_zone('PST8PDT')->ymd('-') . " ==\n";
print "[$tag release-$date.1]\n\n";
foreach my $revision (@revisions) {
    printf "* {{bug|%s}} %s\n", $revision->{bug_id}, $revision->{summary};
}
print "\n\n";

# reminder to merge master -> production
info("before filing the bug, merge master->production branches");
info("after pushing, set the bugzilla-version to today's date (yyyy.mm.dd)");

sub html_escape {
    my ($s) = @_;
    $s =~ s/&/&amp;/g;
    $s =~ s/</&lt;/g;
    $s =~ s/>/&gt;/g;
    return $s;
}
