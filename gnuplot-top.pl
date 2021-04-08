#!/usr/bin/perl
use strict;
use warnings FATAL => 'all';
use File::Temp 'tempfile';
use Data::Dumper;
use List::Util 'pairgrep';
use English qw(-no_match_vars);
use IO::Handle;
use Readonly;
use utf8;
our $VERSION = "1.13";
sub usage {
   print STDERR <<'HELP';
gnuplot-top.pl <process-id> <column>
where column is one of:
   pid
   user
   priority
   nice
   virtual
   resident
   shared
   status
   cpu
   mem
   time
   command
Multiple columns can be specified.
HELP
   exit 1;
}
#Pass in a backslashed variable containing a string
#Returns the changed string.
sub removeAnsiEscapes {
   my ($string) = @ARG;
   #ANSI escape sequences don't use unicode codepoints (I think)
   no utf8;
   $$string =~ s/\e          #Escape character
                 [\[\(]      #Left bracket or parenthesis
                 .*?         #Non-greedy one or more characters
                 [[:alpha:]] #Alphabetic character
                 //gx;
   return $$string;
}
#Read a record from a pipe to 'top' command,
#removing ANSI escape codes as needed.
sub readPipe {
   my ($top) = @ARG;
   my $line = scalar readline $top;
   return removeAnsiEscapes(\$line);
=for comment
   Temporary debugging stuff
   my $copy = $line;
   $copy =~ s/\e/\\e/g;
   print "Line is $copy\n";
   my $cleaned = removeAnsiEscapes(\$line);
   $cleaned =~ s/\e/\\e/g;
   print "Cleaned-up line is $cleaned\n";
   return $cleaned;
=cut
}
Readonly my @columns => qw(PID USER PRIORITY NICE VIRTUAL RESIDENT SHARED STATUS CPU MEMORY TIME COMMAND);
#Validate column argument
#Return whether column is valid
sub checkArg {
   my ($arg) = @ARG;
   #Abbreviations used by `top` for the columns
   my %abbrev = (
      'MEM' => 'MEMORY',
      'PR' => 'PRIORITY',
      'NI' => 'NICE',
      'VIRT' => 'VIRTUAL',
      'RES' => 'RESIDENT',
      'SHR' => 'SHARED',
      'S' => 'STATUS',
   );
   if (defined $abbrev{$$arg}) {
      $$arg = $abbrev{$$arg};
      return 1;
   }
   foreach my $column (@columns) {
      if ($$arg eq $column) {
         return 1;
      }
   }
   return 0;
}
my ($top, $gnuplot);
my $signaled = 0;
sub main {
   local $SIG{INT} = local $SIG{CHLD} =
      sub {$signaled = 1;};
   if (!scalar @ARGV) {
      usage();
   }
   my $startTime = time();
   #"0 + <expr>" converts to a number
   my $wantedPid = 0 + (shift @ARGV);
   my @wantedColumns;
   while (@ARGV) {
      my $wantedColumn = uc(shift @ARGV);
      if (!checkArg(\$wantedColumn)) {
         usage();
      }
      push @wantedColumns, $wantedColumn;
   }
   unless (scalar @wantedColumns) {
      usage();
   }
   my ($plotFile, $plotFilename) = tempfile();
   #Open Top for reading and GNUPlot for writing
   open $top, q{-|}, "top";
   open $gnuplot, q{|-}, "gnuplot";
   #Disable buffering for *STDOUT
   *STDOUT->autoflush();
   #Disable buffering for $gnuplot pipe.
   $gnuplot->autoflush();
   $plotFile->autoflush();
   while (!$signaled && defined(my $line = readPipe($top))) {
      if ($line =~ m/^    #Start of line
                      \s* #Zero or more spaces
                      \d+ #One or more digits/x) {
         my $i = 0;
         my %fields = map {$columns[$i++] => $ARG} splice @{[grep {length($ARG)} split m/\s+ #One or more spaces/x, $line]}, 0, scalar @columns;
         #print Dumper \%fields;
         if ($fields{PID} == $wantedPid) {
            print "Found PID $wantedPid; command was $fields{COMMAND}\n";
            my $timeDiff = time()-$startTime;
            my $plotLine = $timeDiff;
            my $plotCmd = "plot ";
            my $j = 2;
            foreach my $wantedColumn (@wantedColumns) {
               $plotLine .= "\t\t$fields{$wantedColumn}";
               $plotCmd .= "'$plotFilename' using 1:$j with lines title '$wantedColumn of $fields{COMMAND}',";
               $j++;
            }
            print $plotFile "$plotLine\n";
            print $gnuplot "$plotCmd\n";
         }
      }
   }
}
END {
   close $gnuplot if defined $gnuplot;
   close $top if defined $top;
   exit 0;
}
main();
