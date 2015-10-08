package Starman::Server::ZooKeeper;
use strict;
use warnings;
use File::Basename qw(basename);
use Scalar::Util qw(weaken);
use Sys::Hostname ();
use Try::Tiny;
use ZooKeeper;
use ZooKeeper::Constants qw(ZOO_SESSION_EVENT);
use Moo;
use namespace::autoclean;
extends 'Starman::Server';

has zk => (
    is      => 'ro',
    lazy    => 1,
    builder => '_build_zk',
);
sub _build_zk {
    my ($self) = @_;
    my $hosts  = $self->{options}{zk_hosts} // 'localhost:2181';
    return ZooKeeper->new(hosts => $hosts);
}

has zk_path => (
    is      => 'ro',
    lazy    => 1,
    builder => '_build_zk_path',
);
sub _build_zk_path {
    my ($self) = @_;
    return join '/', $self->zk_root, Sys::Hostname::hostname();
}

has zk_root => (
    is      => 'ro',
    lazy    => 1,
    builder => '_build_zk_root',
);
sub _build_zk_root {
    my ($self) = @_;
    return $self->{options}{zk_root} // '/'.basename($0);
}

after idle_loop_hook => sub {
    my ($self) = @_;
    # process any pending events
    1 while $self->zk->dispatcher->dispatch_event;
};

after post_configure_hook => sub {
    my ($self) = @_;

    if (defined( my $log_level = $self->{options}{log_level} )) {
        $self->{server}{log_level} = $log_level;
    }

    my $min  = $self->{server}{min_servers};
    my $max  = $self->{server}{max_servers};
    my $data = _serialize_zk_node($min, $max);

    my $zk = $self->zk;
    $zk->ensure_path($self->zk_path);
    $zk->set($self->zk_path, $data);

    $self->setup_zk_watcher;
};

sub _serialize_zk_node {
    my ($min, $max) = @_;
    return join(',', $min, $max);
}

sub _deserialize_zk_node {
    my ($data) = @_;
    return split(',', $data // '');
}

sub setup_zk_watcher {
    weaken(my $self = shift);

    my $data;
    my $path = $self->zk_path;
    try {
        $data = $self->zk->get($path, watcher => sub { $self->handle_zk_event(@_) });
    } catch {
        $self->log(2, "[pid $$] Error getting ZooKeeper path $path: $_");
    };

    return $data;
}

sub handle_zk_event {
    my ($self, $event) = @_;
    return if $event->{type} == ZOO_SESSION_EVENT;
    if (my $data = $self->setup_zk_watcher) {
        my ($min, $max) = _deserialize_zk_node($data);
        $self->{server}{min_servers} = $min;
        $self->{server}{max_servers} = $max;
    }
}

after child_init_hook => sub {
    my ($self) = @_;
    $self->zk->reopen;

    my $path = $self->zk_path.'/'.$$;
    try {
        $self->zk->create($path, ephemeral => 1);
    } catch {
        $self->log(2, "[pid $$] Error creating $path: $_");
    };
};

1;
