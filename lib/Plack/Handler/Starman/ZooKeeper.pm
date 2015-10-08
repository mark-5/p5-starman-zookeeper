package Plack::Handler::Starman::ZooKeeper;
 
use 5.008_001;
use strict;
use warnings;
use Starman::Server::ZooKeeper;
 
use base 'Plack::Handler::Starman';
 
sub new {
    my $class = shift;
    bless { @_ }, $class;
}
 
sub run {
    my($self, $app) = @_; 
 
    if ($ENV{SERVER_STARTER_PORT}) {
        require Net::Server::SS::PreFork;
        @Starman::Server::ModCluster::ISA = qw(Net::Server::SS::PreFork);
    }   
     
    Starman::Server::ZooKeeper->new->run($app, {%$self});
}
 
1;
