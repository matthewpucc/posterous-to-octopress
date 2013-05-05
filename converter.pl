#!/usr/bin/env perl

use DateTime;
use XML::Simple;
use Data::Dumper;
use Getopt::Long;
use File::Find::Rule;
use Date::Parse;

use strict;

my $htmlToText = "";
my $backupLocation = "";
my $octopressLocation = "";

my $DEBUG = 0;

my $xml = new XML::Simple;

sub parseFile {
  my ($file) = @_;

  my $tmpFile = `mktemp`;
  chomp($tmpFile);

  open my $tmpHandle, "+>", $tmpFile or die "$!";
  open my $fileHandle, "<", $file or die "$!";

  my $content = "<item xmlns:dc=\"http://www.w3.org\" xmlns:wp=\"http://www.w3.org\""
    . " xmlns:excerpt=\"http://www.w3.org\" xmlns:content=\"http://www.w3.org\">\n";

  seek $fileHandle, 7, 0;
  
  while (<$fileHandle>) {
    $content .= $_;
  }

  print $tmpHandle $content;

  close $fileHandle;
  close $tmpHandle;

  print "Generating temporary xml file: $tmpFile\n" if ($DEBUG);;

  my $data = $xml->XMLin($tmpFile);

  unlink $tmpFile if ($DEBUG);

  return $data;
}

sub convertContent {
  my $content = shift;

  my $html = $content;

  my $tempHTML = `mktemp`;
  chomp($tempHTML);

  print "Generating html file: $tempHTML\n" if ($DEBUG);

  #$html =~ s/[\x01-\x03\x05-\x08\x10-\x19\x80-\xff]//g;

  open my $htmlHandle, ">", $tempHTML or die "$!";
  print $htmlHandle $html;
  close $htmlHandle;

  my $results = `python $htmlToText < $tempHTML`;

	unlink $tempHTML if ($DEBUG);;

  return $results;
}

sub convertDate {
  my $date = shift;

  my $epoch = str2time($date);

  my $dateTime = DateTime->from_epoch(epoch =>  $epoch);

  return $dateTime;
}

sub writeMetaData {
  my ($data, $file, $pubDate) = @_;

  my $date = $pubDate->ymd() . " " . $pubDate->hour . ":" . $pubDate->minute;

  my $categories = "";
  foreach my $category (@{$data->{category}}) {
    next if (ref($category) ne "HASH"); # fixes duplicate Uncategorized bug
    $categories .= "- $category->{content}\n";
  }

  print $file qq{---
layout: post
title: "$data->{title}"
date: $date
comments: true
categories: 
$categories
---
};
}

sub createPostFile {
  my ($title, $pubDate) = @_;

  my $post = lc($title);
  $post =~ s/ /-/g;
  $post = $octopressLocation . "/source/_posts/" . $pubDate->ymd() . "-" . $post . ".markdown";

  open my $postHandle, ">", $post or die "$!";

  return $postHandle;
}

GetOptions ("backup=s" => \$backupLocation,
            "octopress=s" => \$octopressLocation,
            "html2text=s" => \$htmlToText);

unless (-d $backupLocation && -d $octopressLocation && -x $htmlToText) {
	print "Received vars: backup ($backupLocation) octopress ($octopressLocation) htmltotext ($htmlToText)\n";
  die "Usage: $0 --backup <export location> --octopress <octopress loction> --html2text <html2text location>";
}

my @postFolders =  File::Find::Rule->directory()->name('posts')->in($backupLocation);

foreach my $folder (@postFolders) {
  my @files = File::Find::Rule->file()->name('*.xml')->maxdepth(1)->in($folder);

  foreach my $file (@files) {
    print "Found file: $file\n" if ($DEBUG);
    my $data = parseFile($file);

    my $markdown = convertContent($data->{"content:encoded"});

    my $pubDate = convertDate($data->{pubDate});

    my $postFile = createPostFile($data->{title}, $pubDate);

    writeMetaData($data, $postFile, $pubDate);

    print $postFile "\n$markdown";

    close $postFile;

    print "Generated post for $data->{title}\n";
  }
}