package App::ManagePoolStyleRepo;

# AUTHORITY
# DATE
# DIST
# VERSION

use 5.010001;
use strict;
use warnings;
use Log::ger;

use Cwd;
use File::chdir;
use File::Slurper qw(read_text);
use Hash::Subset qw(hash_subset);
use Regexp::Pattern::Path;

my $re_filename_unix = $Regexp::Pattern::Path::RE{filename_unix}{pat};

our %SPEC;

our %args_common = (
    repo_path => {
        schema => 'dirname*',
        req => 1,
        pos => 0,
        summary => 'Repo directory',
    },
);

our %argopt_detail = (
    detail => {
        schema => 'bool*',
        cmdline_aliases => {l=>{}},
    },
);

$SPEC{get_item_metadata} = {
    item_path => {
        schema => 'filename*',
        req => 1,
        pos => 0,
    },
    result_naked => 1,
};
sub get_item_metadata {
    my %args = @_;
    my $path = $args{item_path};

    my $filename;
    if ($args{_skip_cd}) {
        $filename = $path;
    } else {
        my $abs_path = Cwd::abs_path($path);
        ($filename = $abs_path) =~ s!./!!;
    }

    my $res = {};
    $res->{filename} = $filename;
    $res->{title} = $filename;

    if (-d $path) {
        local $CWD = $path;
        if (-f ".title") {
            (my $title = read_text(".title")) =~ s/\R+//g;
            die "$path: Invalid title in .title: invalid filename"
                unless $title =~ $re_filename_unix;
            $res->{title} = $title;
        }
        my @tag_files = glob ".tag-*";
        $res->{tags} = [map { s/\A\.tag-//; $_ } @tag_files] if @tag_files;
    } else {
    }
    $res;
}

$SPEC{list_items} = {
    v => 1.1,
    args => {
        %args_common,
        %argopt_detail,

        has_tags => {
            'x.name.is_plural' => 1,
            'x.name.singular' => 'has_tag',
            schema => ['array*', of=>'str*'],
            tags => ['category:filtering'],
        },
        lacks_tags => {
            'x.name.is_plural' => 1,
            'x.name.singular' => 'lacks_tag',
            schema => ['array*', of=>'str*'],
            tags => ['category:filtering'],
        },
        q => {
            summary => 'Search query',
            schema => 'str*',
            pos => 1,
            tags => ['category:filtering'],
        },

        _searchable_fields => {
            schema => ['array*', of=>'str*'],
            default => ['filename', 'title'],
            tags => ['hidden'],
        },
    },
    features => {
    },
};
sub list_items {
    my %args = @_;

    my $q_lc; $q_lc = lc $args{q} if defined $args{q};
    my $searchable_fields = $args{_searchable_fields} // ['filename', 'title'];

    local $CWD = $args{repo_path};

    my @rows;

  POOL:
    {
        last unless -d "pool";
        local $CWD = "pool";
        for my $item_path (glob "*") {
            my $row;
            $row = get_item_metadata(item_path=>$item_path, _skip_cd=>1);
            push @rows, $row;
        }
    }

  POOL1:
    {
        last unless -d "pool1";
        local $CWD = "pool1";
        for my $dir1 (grep {-d} glob "*") {
            local $CWD = $dir1;
            for my $item_path (glob "*") {
                my $row;
                $row = get_item_metadata(item_path=>$item_path, _skip_cd=>1);
                $row->{dir} = $dir1;
                push @rows, $row;
            }
        }
    }

  POOL2:
    {
        last unless -d "pool2";
        local $CWD = "pool2";
        for my $dir1 (grep {-d} glob "*") {
            local $CWD = $dir1;
            for my $dir2 (grep {-d} glob "*") {
                local $CWD = $dir2;
                for my $item_path (glob "*") {
                    my $row;
                    $row = get_item_metadata(item_path=>$item_path, _skip_cd=>1);
                    $row->{dir} = "$dir1/$dir2";
                    push @rows, $row;
                }
            }
        }
    }

  FILTER: {
        my @frows;
      ROW:
        for my $row (@rows) {
            if ($args{has_tags}) {
                my $matches;
                for my $tag (@{ $args{has_tags} }) {
                    do { $matches++; last } if $row->{tags} &&
                        grep { $tag eq $_ } @{ $row->{tags} };
                }
                next ROW unless $matches;
            }
            if ($args{lacks_tags}) {
                my $matches = 1;
                for my $tag (@{ $args{lacks_tags} }) {
                    do { $matches = 0; last } if $row->{tags} &&
                        grep { $tag eq $_ } @{ $row->{tags} };
                }
                next ROW unless $matches;
            }
            if (defined $q_lc) {
                my $matches;
                for my $field (@$searchable_fields) {
                    do { $matches++; last } if defined $row->{$field} && index(lc($row->{$field}), $q_lc) >= 0;
                }
                next ROW unless $matches;
            }
            push @frows, $row;
        }
        @rows = @frows;
    }

    unless ($args{detail}) {
        @rows = map { $_->{title} } @rows;
    }

    [200, "OK", \@rows];
}

1;
# ABSTRACT: Manage pool-style repo directory
