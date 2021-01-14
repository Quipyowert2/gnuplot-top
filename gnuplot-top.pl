#!/usr/bin/perl
use strict;
use warnings FATAL => 'all';
use File::Temp 'tempfile';
use Data::Dumper;
use List::Util 'pairgrep';
use English qw(-no_match_vars);
use IO::Handle;
use utf8;
our $VERSION = "1.06";
use constant {
   PID => 0,
   USER => 1,
   PRIORITY => 2,
   NICE => 3,
   VIRTUAL => 4,
   RESIDENT => 5,
   SHARED => 6,
   STATUS => 7,
   CPU => 8,
   MEMORY => 9,
   TIME => 10,
   NAME => 11,
   READ_PIPE => "-|",
   WRITE_PIPE => "|-",
};
sub usage {
   print STDERR <<HELP;
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
#Validate column argument
#Return whether column is valid
sub checkArg {
   my ($arg) = @ARG;
   #Most of these except for COMMAND are
   #abbreviations used by `top` for the columns
   my %abbrev = (
      'MEM' => 'MEMORY',
      'PR' => 'PRIORITY',
      'NI' => 'NICE',
      'VIRT' => 'VIRTUAL',
      'RES' => 'RESIDENT',
      'SHR' => 'SHARED',
      'S' => 'STATUS',
      'COMMAND' => 'NAME',
   );
   if (defined $abbrev{$$arg}) {
      $$arg = $abbrev{$$arg};
      return 1;
   }
   foreach my $column (qw(PID USER PRIORITY NICE VIRTUAL RESIDENT SHARED STATUS CPU MEMORY TIME COMMAND)) {
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
   my $wantedColumn = uc(shift @ARGV);
   if (!checkArg(\$wantedColumn)) {
      usage();
   }
   my ($plotFile, $plotFilename) = tempfile();
   #Open Top for reading and GNUPlot for writing
   open $top, READ_PIPE, "top";
   open $gnuplot, WRITE_PIPE, "gnuplot";
   #Disable buffering for *STDOUT
   *STDOUT->autoflush();
   #Disable buffering for $gnuplot pipe.
   $gnuplot->autoflush();
   $plotFile->autoflush();
   while (!$signaled && defined(my $line = readPipe($top))) {
      if ($line =~ m/^    #Start of line
                      \s* #Zero or more spaces
                      \d+ #One or more digits/x) {
         my $i = -1;
         my @records = grep {length($ARG)} split m/\s+ #One or more spaces/x, $line;
         my %record;
         $record{PID} = $records[0];
         $record{USER} = $records[1];
         $record{PRIORITY} = $records[2];
         $record{NICE} = $records[3];
         $record{VIRTUAL} = $records[4];
         $record{RESIDENT} = $records[5];
         $record{SHARED} = $records[6];
         $record{STATUS} = $records[7];
         $record{CPU} = $records[8];
         $record{MEMORY} = $records[9];
         $record{TIME} = $records[10];
         $record{NAME} = $records[11];
         #print Dumper \%record;
         if ($record{PID} == $wantedPid) {
            print "Found PID $wantedPid; command was $record{NAME}\n";
            my $timeDiff = time()-$startTime;
            my $plotLine = "$timeDiff\t\t$record{$wantedColumn}\n";
            print $plotFile $plotLine;
            print $gnuplot "plot '$plotFilename' with lines title '$wantedColumn of $record{NAME}'\n";
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
