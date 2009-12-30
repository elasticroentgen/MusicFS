#!/usr/bin/perl

use warnings;
use strict;

use POSIX;
use Fuse;
use Data::Dumper;
use MP3::Tag;

$| = 1;

############ SETUP ############
my $basedir = "/home/thereapman/Netz/Musik/";

############ DON'T EDIT BELOW THIS LINE  ############

my $filesystem = {
	root =>
	{
		content =>
		{
			genre =>
			{
				type => 'dir'
			},
			artist =>
			{
				type => 'dir'
			},
			year =>
			{
				type => 'dir'
			},
			fsinfo =>
			{
				type => 'file',
				content => 'MusicFS - 0 files in db\n'
			}
		}
	}
};

my $lastAttredFile;

sub my_getattr {
	my ( $filename ) = @_;
	print "==ATTRIBUTES==>$filename ";

	# regulaere Datei
	my $type = 0100;

	# owner: r/w, group: r, others: r
	my $bits = 0444;

	# falls Verzeichnis, type auf dir setzen,
	# mode auf 0755:
	# owner: r/w/x, group: r/x, others: r/x
	my $current = $filesystem->{'root'}->{'content'};
	my @pathElements = split( '/', $filename );
	my $currentType = 'file';

	if ( @pathElements > 1 ) {
		foreach my $pathElement ( @pathElements[1..$#pathElements] ) {

			if ( !defined( $current->{$pathElement} ) ) {
                print "not found!\n";
				return -1*ENOENT;
			}
			$currentType = $current->{$pathElement}->{'type'};
			$lastAttredFile = $current->{$pathElement} if ( $currentType eq 'file' );

			$current = $current->{$pathElement}->{'content'} if ( $currentType eq 'dir' );
		}
	}

	if ( $filename eq '/' || $currentType eq 'dir' ) {
		$type = 0040;
		$bits = 0555;
	} 
	#my $mode = $type << 9 | $bits;
	my $mode = $type << 9 | $bits;
	my $nlink = 1;

	# reale UID (siehe perlvar)
	my $uid = $<;

	# reale GID (siehe perlvar)
	my ($gid) = split / /, $(;

	# Geraete-ID (special files only)
	my $rdev = 0;

	# letzter Zugriff
	my $atime = time;

	# Groeße
	my $size = 0;

	if ( $currentType eq 'file' && $filename ne '/') {
		$size = -s $lastAttredFile->{'content'};
	}

	# letzte Aenderung
	my $mtime = $atime;

	# letzte Aenderung Inode
	my $ctime = $atime;

	my $blksize = 1024;
	my $blocks = 1;
	
	my $dev = 0;
	my $ino = 0;
    print "is a $currentType of size $size Bytes\n";
	return ( $dev, $ino, $mode, $nlink, $uid, $gid, $rdev, $size, $atime, $mtime, $ctime, $blksize,	$blocks	);
}

sub my_getdir {
	my ( $filename ) = @_;
	print "==GETDIR==>$filename\n";

	my $current = $filesystem->{'root'}->{'content'};
	my @pathElements = split( '/', $filename );

	if ( @pathElements > 1 ) {
		foreach my $pathElement ( @pathElements[1..$#pathElements] ) {
			return( -1*ENOENT ) if ( !defined( $current->{$pathElement} ) );
			$current = $current->{$pathElement}->{'content'};
		}
	}

	return( '.', keys( %{$current} ), 0 );
}

sub my_read {
	my ( $filename, $reqsize, $offset ) = @_;
	my $original_file = $lastAttredFile->{'content'};
	open(ORG, $original_file);
	binmode(ORG);
	seek(ORG, $offset,1);

	my $return;	
	my $readed = read(ORG,$return,$reqsize);
	
	close(ORG);
	print "==READING==>$original_file ($reqsize bytes from offset $offset >> $readed bytes readed)\n";
	return $return;
	
}

print "MusicFS 0.1\n";
print "Reading Basedirectory...\n";

my @basedir_content;

open(BASEDIR, "find $basedir -name *.mp3|");

while(<BASEDIR>)
{
    chop();
    push(@basedir_content, $_);    
}

close(BASEDIR);

my $genres = {};
my $years = {};
my $artists = {};

foreach my $file (@basedir_content)
{
	if($file eq ".." || $file eq ".")
	{
		next;
	}
    
    print "==ADDING==>";
	my $filetag = MP3::Tag->new($file);
    if(!defined $filetag)
    {
        print "No readable Tag. Skipping file!\n";
        next;
    }

	$filetag->get_tags();
	if(exists $filetag->{ID3v1})
	{
		my $genre = $filetag->{ID3v1}->genre;
		my $artist = $filetag->{ID3v1}->artist;
		my $title = $filetag->{ID3v1}->title;
		my $year = $filetag->{ID3v1}->year;
	
		print "$artist - $title\n";
			
		if(!exists $filesystem->{root}->{content}->{genre}->{content}->{$genre})
		{
			$filesystem->{root}->{content}->{genre}->{content}->{$genre}->{type} = 'dir';
		}
		$filesystem->{root}->{content}->{genre}->{content}->{$genre}->{content}->{"$artist-$title.mp3"}->{type} = 'file';
		$filesystem->{root}->{content}->{genre}->{content}->{$genre}->{content}->{"$artist-$title.mp3"}->{content} = $file;

	}
	else
	{	
		print "No IDv1 Tag. Skipping file!\n";
	}
	
}

Fuse::main(
	mountpoint  => "/mnt/testmnt",
	getdir		=> \&my_getdir,
	getattr		=> \&my_getattr,
	read		=> \&my_read,
	debug => 0
);

