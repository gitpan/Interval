#!perl -w
#------------------------------------------------------------------------------
#
# Copyright (C) 1997 by Kristian Torp, torp@cs.auc.dk
# 
#    This program is free software. You can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation; either version 2 of the License, or
#    (at your option) any later version.
# 
#    This program is distributed AS IS in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY. See the GNU General Public License for more 
#    details.
#
#------------------------------------------------------------------------------

package Date::Interval;
require Exporter;
use strict;
use vars qw (@ISA @EXPORT @EXPORT_OK $VERSION
	     $FALSE $TRUE $ABSOLUTE $RELATIVE
	     $OPEN $CLOSED $LEFT_CLOSED $RIGHT_CLOSED $LEFT_OPEN $RIGHT_OPEN 
	     $CLOSED_INT $RIGHT_OPEN_INT $LEFT_OPEN_INT $OPEN_INT
	     $BEFORE $MEETS $LEFT_OVERLAPS $RIGHT_OVERLAPS
	     $TOTALLY_OVERLAPS $DURING $EXTENDS $AFTER
	     $ALLEN_BEFORE $ALLEN_MEETS $ALLEN_LEFT_OVERLAPS $ALLEN_LEFT_COVERS
	     $ALLEN_COVERS $ALLEN_STARTS $ALLEN_EQUALS $ALLEN_RIGHT_COVERS 
	     $ALLEN_DURING $ALLEN_FINISHES $ALLEN_RIGHT_OVERLAPS
	     $ALLEN_EXTENDS $ALLEN_AFTER
	     $DisplayFormat $DefaultType $Now); 
@ISA    = qw (Exporter);
@EXPORT = qw ();
@EXPORT_OK = qw ($CLOSED_INT $RIGHT_OPEN_INT $LEFT_OPEN_INT $OPEN_INT
		 $BEFORE $MEETS $LEFT_OVERLAPS $RIGHT_OVERLAPS
		 $TOTALLY_OVERLAPS $DURING $EXTENDS $AFTER
		 $ALLEN_BEFORE $ALLEN_MEETS $ALLEN_LEFT_OVERLAPS $ALLEN_LEFT_COVERS
		 $ALLEN_COVERS $ALLEN_STARTS $ALLEN_EQUALS $ALLEN_RIGHT_COVERS 
		 $ALLEN_DURING $ALLEN_FINISHES $ALLEN_RIGHT_OVERLAPS
		 $ALLEN_EXTENDS $ALLEN_AFTER);
$VERSION = 0.02;

use Date::Manip; # data types of the end points in the interval
use Carp;

use overload
    '+'   => \&_plus,
    '-'   => \&_minus,
    '<'   => \&_smaller_than,
    '>'   => \&_greater_than,
    '=='  => \&_equal,
    '!='  => \&_not_equal,
    '<=>' => \&_spaceship,
    qw("" _stringify);

# Must set the time zone to use Date::Manip
BEGIN {$Date::Manip::TZ = "CET";} # Default Central European Time

##############################################################################
# Constants
##############################################################################

# Boolean values
$FALSE = 0;
$TRUE  = 1;

# <value type>
$ABSOLUTE = 0;
$RELATIVE = 1;

# For output
$LEFT_CLOSED  = '[';
$RIGHT_CLOSED = ']';
$LEFT_OPEN    = '(';
$RIGHT_OPEN   = ')';

# <interval type>
$CLOSED_INT     = 1;
$RIGHT_OPEN_INT = 2;
$LEFT_OPEN_INT  = 3;
$OPEN_INT       = 4;

# <interval end>
$OPEN   = 1;
$CLOSED = 2;

# <overlap type>
$BEFORE           = 1;
$MEETS            = 2;
$LEFT_OVERLAPS    = 3;
$RIGHT_OVERLAPS   = 4;
$TOTALLY_OVERLAPS = 5;
$DURING           = 6;
$EXTENDS          = 7;
$AFTER            = 8;

# <Allen overlap type>
$ALLEN_BEFORE         = 1;
$ALLEN_MEETS          = 2;
$ALLEN_LEFT_OVERLAPS  = 3;
$ALLEN_LEFT_COVERS    = 4;
$ALLEN_COVERS         = 5;
$ALLEN_STARTS         = 6;
$ALLEN_EQUALS         = 7;
$ALLEN_RIGHT_COVERS   = 8;
$ALLEN_DURING         = 9;
$ALLEN_FINISHES       = 10;
$ALLEN_RIGHT_OVERLAPS = 11;
$ALLEN_EXTENDS        = 12;
$ALLEN_AFTER          = 13;

##############################################################################
# Class variables
##############################################################################

$DisplayFormat = "%d/%m/%Y";                 # Default <display format>
$DefaultType   = $RIGHT_OPEN_INT;            # Default <interval type>
$Now           = &_getCurrentTime ($FALSE);  # Big brother time, see POD 
                
##############################################################################
# Class Methods
##############################################################################

sub setDefaultIntervalType
{
    my $class = shift;
    my ($nType) = @_;
    
    if (ref ($class))             { confess "Class method called as object method"; }
    if ($nType < 1 || $nType > 4) { confess "Unknown <interval type> $nType"; }
    $DefaultType = $nType;
}

sub getDefaultIntervalType
{ 
    my $class = shift;
    if (ref ($class)) { confess "Class method called as object method"; }
    return $DefaultType;
}

sub setDisplayFormat
{
    my $class = shift;
    if (ref ($class)) { confess "Class method called as object method"; }
    unless (@_ == 1)  { confess "usage: Interval->setDisplayFormat(<string>)"; }
    $DisplayFormat = shift;
}

sub getDisplayFormat
{ 
    my $class = shift;
    if (ref ($class)) { confess "Class method called as object method"; }
    return $DisplayFormat;
}

#-----------------------------------------------------------------------------
# Instance variables
#-----------------------------------------------------------------------------

my %fields = (m_nStart => undef,   # Start value
              m_nStop  => undef,   # Stop value
	      m_bStart => undef,   # Start absolute or relative 
	      m_bStop  => undef,   # Stop absolute or relative
	      m_nLeft  => undef,   # Left open or closed  <interval end>
	      m_nRight => undef,   # Right open or closed <interval end>
	      m_bEmpty => undef);  # is the interval empty

#-----------------------------------------------------------------------------
# Initialization
# Input:  start value stop value [<interval type>]
#-----------------------------------------------------------------------------
   
sub new
{
    my $proto = shift;
    my $class = ref ($proto) || $proto;
    my $self = {};
    bless ($self, $class);
    $self->_initialize (@_);
    return $self;
}
 
sub _initialize
{
    my $self = shift;
    my($szStart, $szStop, $nType) = @_;

    $self->{m_bEmpty} = $FALSE;

    # Parse the interval end points
    ($self->{m_nStart},	$self->{m_bStart}) = _getEndPoint($szStart);
    if (!defined ($self->{m_nStart})) 
    { 
	print STDERR "Problems using $szStart as start value\n"; 
	$self->{m_bEmpty} = $TRUE;
    }

    ($self->{m_nStop},	$self->{m_bStop}) = _getEndPoint($szStop);
    if (!defined ($self->{m_nStop})) 
    { 
	print STDERR "Problems using $szStop as stop value\n"; 
	$self->{m_bEmpty} = $TRUE;
    }

    # Check the end point values
    my $start = _to_date ($FALSE, $self->{m_bStart}, $self->{m_nStart});
    my $stop  = _to_date ($TRUE,  $self->{m_bStop}, $self->{m_nStop}, $self->{m_bStart}, $start);

    if ($self->{m_bStop} == $ABSOLUTE && $start gt $stop)
    {
	die "Start date larger than stop date\n";
    }
    
    # Use the default <interval type>?
    if (!defined($nType)) { $nType = $DefaultType; }
    if (!$self->_setIntervalType ($nType)) 
    {
	print STDERR "Problems setting the <interval type> $nType\n";
    }
}

#-----------------------------------------------------------------------------
# Creates a new empty interval
# Input:  none
# Output: empty <interval>
#-----------------------------------------------------------------------------

sub _new_empty
{
    my $proto = shift;
    my $class = ref ($proto) || $proto;
    my $self = {};
    bless ($self, $class);
    $self->{m_bEmpty} = $TRUE;
    return $self;
}

#-----------------------------------------------------------------------------
# Sets the <interval type>
# Input:  <interval type>
# Output: boolean
#-----------------------------------------------------------------------------

sub _setIntervalType
{
    my $self = shift;
    my ($nType) = @_;
    
    if ($nType == $CLOSED_INT) 
    {
	$self->{m_nLeft}  = $CLOSED;
	$self->{m_nRight} = $CLOSED; 
    }
    elsif ($nType == $RIGHT_OPEN_INT) 
    {
	$self->{m_nLeft}  = $CLOSED;
	$self->{m_nRight} = $OPEN; 
    }
    elsif ($nType == $LEFT_OPEN_INT) 
    {
	$self->{m_nLeft}  = $OPEN;
	$self->{m_nRight} = $CLOSED; 
    }
    elsif ($nType == $OPEN_INT) 
    {
	$self->{m_nLeft}  = $OPEN;
	$self->{m_nRight} = $OPEN; 
    }
    else
    {
	return $FALSE;
    }
    return $TRUE;
}

#-----------------------------------------------------------------------------
# Sets the interval brackets
# Input:  <interval end> <interval end>
# Output: boolean
#-----------------------------------------------------------------------------

sub _setBrackets
{
    my $self = shift;
    my ($nLeft, $nRight) = @_;
    $self->{m_nLeft}  = $nLeft;
    $self->{m_nRight} = $nRight;
    return $TRUE;
}

#-----------------------------------------------------------------------------
# Length of interval in Date::Manip format
# Input:  none
# Output: <delta>
#-----------------------------------------------------------------------------
 
sub length
{
    my $self = shift;
    # Return 0 length 
    if ($self->{m_bEmpty}) { return &DateCalc (&_getCurrentTime($TRUE), &_getCurrentTime($TRUE)); }
    
    my ($startDate) = _to_date ($FALSE, $self->{m_bStart}, $self->{m_nStart});
    my ($stopDate)  = _to_date ($TRUE, $self->{m_bStop}, $self->{m_nStop},
				$self->{m_bStart}, $startDate);

    if ($startDate lt $stopDate)
    {
	return &DateCalc ($startDate, $stopDate);
    }    
    else
    {
	return &DateCalc (&_getCurrentTime($TRUE), &_getCurrentTime($TRUE));
    }
}

#-----------------------------------------------------------------------------
# Length of interval in string format
# Input:  none
# Output: string
#-----------------------------------------------------------------------------
 
sub lengthString
{
    my $self = shift;
    if ($self->{m_bEmpty}) { return ''; }
    my $delta = $self->length;
    my ($nYears, $nMonths, $nDays, $nHours, $nMinuts, $nSeconds) = split (':', $delta);
    $nYears =~ s/^[+|-]//;
    return "$nYears Years $nMonths Months $nDays Days $nHours Hours $nMinuts Minuts $nSeconds Seconds";
    return $delta;
}

#-----------------------------------------------------------------------------
# Returns the interval in string format
# Input:   none
# Output:  string
#-----------------------------------------------------------------------------

sub get
{
    my $self = shift;
    my ($szResult) = '';
    my ($sep) = defined ($,) ? $, : ','; # Which separtor
    if ($self->{m_bEmpty}) { return '<empty>'; }

    if ($self->{m_nLeft} == $CLOSED) { $szResult .= $LEFT_CLOSED; }
    else                             { $szResult .= $LEFT_OPEN; }

    $szResult .= _to_string ($self->{m_bStart}, $self->{m_nStart});
    $szResult .= "$sep ";
    $szResult .= _to_string ($self->{m_bStop}, $self->{m_nStop});

    if ($self->{m_nRight} == $CLOSED) { $szResult .= $RIGHT_CLOSED; }
    else                              { $szResult .= $RIGHT_OPEN; }

    return $szResult;
}

#-----------------------------------------------------------------------------
# Returns the start point
# Input:   none
# Output:  <date>
#-----------------------------------------------------------------------------

sub getStart
{
    my $self = shift;
    return $self->{m_nStart};
}

#-----------------------------------------------------------------------------
# Returns the stop point
# Input:   none
# Output:  <date>
#-----------------------------------------------------------------------------

sub getStop
{
    my $self = shift;
    return $self->{m_nStop};
}

#-----------------------------------------------------------------------------
# Checks if two intervals overlap
# Input:  <interval>
# Output: boolean
#-----------------------------------------------------------------------------

sub overlaps
{
    my $self  = shift;
    my $other = shift;
    if ($self->{m_bEmpty} || $other->{m_bEmpty}) { return $FALSE; }

    if ($self->_overlaps ($other)) { return $TRUE; }
    else                           { return $FALSE; }
}

#-----------------------------------------------------------------------------
# Return the overlap of two intervals
# Input:  <interval>
# Output: <interval> | empty
#-----------------------------------------------------------------------------

sub getOverlap
{
    my $self = shift;
    my $other = shift;
    my ($nStart, $nStop, $nLeft, $nRight);

    if ($self->{m_bEmpty} || $other->{m_bEmpty}) { return _new_empty Date::Interval; }

    if ($self->{m_bStart} == $RELATIVE  || $self->{m_bStop} == $RELATIVE ||
	$other->{m_bStart} == $RELATIVE || $other->{m_bStop} == $RELATIVE)
    {
	print STDERR "Sorry, overlap of relative intervals not implemented yet\n";
	return _new_empty Date::Interval;
    }

    # Meets
    if ($self->{m_nStop} eq $other->{m_nStart} &&
        ($self->{m_nRight} == $CLOSED  ||  $other->{m_nLeft} == $CLOSED))
    {
	$nStart = $nStop = $self->{m_nStop};
	$nLeft  = $self->{m_nRight};
	$nRight = $other->{m_nLeft};
    }
    # Extends
    elsif ($self->{m_nStart} eq $other->{m_nStop} &&
	   ($self->{m_nLeft} == $CLOSED || $other->{m_nRight} == $CLOSED))
    {
	$nStart = $nStop = $self->{m_nStart};
	$nLeft  = $self->{m_nLeft};
	$nRight = $other->{m_nRight};
    }
   # Overlaps
    elsif ($self->{m_nStart} le $other->{m_nStop} &&
	   $other->{m_nStart} le $self->{m_nStop})
    {
	# Max start time
	if ($other->{m_nStart} lt $self->{m_nStart}) { $nStart = $self->{m_nStart}; }
	else                                         { $nStart = $other->{m_nStart}; }
        # left bracket
	if ($self->{m_nLeft} == $OPEN || $other->{m_nLeft} == $OPEN) { $nLeft = $OPEN; }
	else                                                         { $nLeft = $CLOSED; }

	
	# Min stop time
	if ($other->{m_nStop} lt $self->{m_nStop}) { $nStop = $other->{m_nStop}; }
	else                                       { $nStop = $self->{m_nStop}; }

	# right bracket
	if ($self->{m_nRight} == $OPEN || $other->{m_nRight} == $OPEN) { $nRight = $OPEN; }
	else                                                           { $nRight = $CLOSED; }
	
	my $int = new Date::Interval ($nStart, $nStop);
	$int->_setBrackets ($nLeft, $nRight);

	return $int;
    }
    else 
    {
	return _new_empty Date::Interval;
    }
}

#-----------------------------------------------------------------------------
# Examines if interval is before
# Input:  <interval>
# Output: boolean
#-----------------------------------------------------------------------------

sub before
{
    my $self = shift; my $other = shift;
    $self->_overlaps ($other) == $BEFORE ? return $TRUE : return $FALSE;
}

#-----------------------------------------------------------------------------
# Examines if interval meets
# Input:  <interval>
# Output: boolean
#-----------------------------------------------------------------------------

sub meets
{
    my $self = shift; my $other = shift;
    $self->_overlaps ($other) == $MEETS ? return $TRUE : return $FALSE;
}

#-----------------------------------------------------------------------------
# Examines if intervals left overlaps
# Input:  <interval>
# Output: boolean
#-----------------------------------------------------------------------------

sub leftOverlaps
{
    my $self = shift; my $other = shift;
    $self->_overlaps ($other) == $LEFT_OVERLAPS ? return $TRUE : return $FALSE;
}

#-----------------------------------------------------------------------------
# Examines if intervals right overlaps
# Input:  <interval>
# Output: boolean
#-----------------------------------------------------------------------------

sub rightOverlaps
{
    my $self = shift; my $other = shift;
    $self->_overlaps ($other) == $RIGHT_OVERLAPS ? return $TRUE : return $FALSE;
}

#-----------------------------------------------------------------------------
# Examines if intervals during overlaps
# Input:  <interval>
# Output: boolean
#-----------------------------------------------------------------------------

sub during
{
    my $self = shift; my $other = shift;
    $self->_overlaps ($other) == $DURING ? return $TRUE : return $FALSE;
}

#-----------------------------------------------------------------------------
# Examines if intervals right overlaps
# Input:  <interval>
# Output: boolean
#-----------------------------------------------------------------------------

sub totallyOverlaps
{
    my $self = shift; my $other = shift;
    $self->_overlaps ($other) == $TOTALLY_OVERLAPS ? return $TRUE :  return $FALSE;
}

#-----------------------------------------------------------------------------
# Examines if intervals extends
# Input:  <interval>
# Output: boolean
#-----------------------------------------------------------------------------

sub extends
{
    my $self = shift; my $other = shift;
    $self->_overlaps ($other) == $EXTENDS ? return $TRUE :  return $FALSE;
}

#-----------------------------------------------------------------------------
# Examines if interval after
# Input:  <interval>
# Output: boolean
#-----------------------------------------------------------------------------

sub after
{
    my $self = shift; my $other = shift;
    $self->_overlaps ($other) == $EXTENDS ? return $TRUE :  return $FALSE;
}

#-----------------------------------------------------------------------------
# Examines how intervals overlaps
# Input:  <interval>
# Output: <overlap type> || FALSE
#-----------------------------------------------------------------------------

sub _overlaps
{
    my $self = shift;
    my $other = shift;
    my ($bHowOverlaps, $bLeft);
    $bHowOverlaps = $bLeft = $FALSE;

    if ($self->{m_bEmpty} || $other->{m_bEmpty}) { return $FALSE; }

    my $start1 = _to_date ($FALSE, $self->{m_bStart}, $self->{m_nStart});
    my $stop1  = _to_date ($TRUE,  $self->{m_bStop}, $self->{m_nStop}, $self->{m_bStart}, $start1);
    my $start2 = _to_date ($TRUE,  $other->{m_bStart}, $other->{m_nStart});
    my $stop2  = _to_date ($TRUE,  $other->{m_bStop}, $other->{m_nStop}, $other->{m_bStart}, $start2);
    
    # Meets
    if ($stop1 eq $start2 &&
	($self->{m_nRight} == $CLOSED || $other->{m_nLeft} == $CLOSED))
    {
	$bHowOverlaps = $MEETS;
    }
    # Extends
    elsif ($start1 eq $stop2 &&
	   ($self->{m_nLeft} == $CLOSED || $other->{m_nRight} == $CLOSED))
    {
	$bHowOverlaps = $EXTENDS;
    }
   # Overlaps
    elsif ($start1 le $stop2 && $start2 le $stop1)
    {
	$bHowOverlaps = $TOTALLY_OVERLAPS; # A guess

	# Left overlap or inclusion
	if ($start2 le $stop1 && $stop1 le $stop2)
	{
	    $bHowOverlaps = $LEFT_OVERLAPS; # A guess
	    $bLeft = $TRUE;                 # Saved for inclusion
	}
	# Right overlap or inclusion
	if ($start2 le $start1 && $start1 le $stop2)
	{
	    $bHowOverlaps = $bLeft ? $DURING : $RIGHT_OVERLAPS;
	}
    }
    return $bHowOverlaps;
}

#-----------------------------------------------------------------------------
# Describes in text how intervals overlaps
# Input:  <interval>
# Output: to screen
#-----------------------------------------------------------------------------

sub howOverlaps
{
    my $self  = shift;
    my $other = shift;
    my ($szOverlap) = ' does not overlap ';
    if ($self->{m_bEmpty} || $other->{m_bEmpty}) 
    { 
	print $self->get,  $szOverlap, $other->get, "\n";
    }
    else
    {
	my ($bOverlaps) = $self->_overlaps($other);
	
	if    ($bOverlaps == $MEETS)           { $szOverlap = ' meets '; }
	elsif ($bOverlaps == $LEFT_OVERLAPS)   { $szOverlap = ' left overlaps '; }
	elsif ($bOverlaps == $RIGHT_OVERLAPS)  { $szOverlap = ' right overlaps '; }
	elsif ($bOverlaps == $TOTALLY_OVERLAPS){ $szOverlap = ' totally overlaps '; }   
	elsif ($bOverlaps == $DURING)          { $szOverlap = ' inclusion overlaps '; }
	elsif ($bOverlaps == $EXTENDS)         { $szOverlap = ' extends '; }
	print $self->get,  $szOverlap, $other->get, "\n";
    }
}

#-----------------------------------------------------------------------------
# Finds how intervals overlap in Allen terminology
# Input:  none
# Output: <Allen overlap type> string
#-----------------------------------------------------------------------------

sub _AllenOverlaps
{
    my $self = shift;
    my $other = shift;
    my ($bHowOverlaps) = $FALSE;

    if ($self->{m_bEmpty} || $other->{m_bEmpty}) { return $FALSE; }

    my $start1 = _to_date ($FALSE, $self->{m_bStart}, $self->{m_nStart});
    my $stop1  = _to_date ($TRUE, $self->{m_bStop}, $self->{m_nStop}, $self->{m_bStart}, $start1);
    my $start2 = _to_date ($TRUE, $other->{m_bStart}, $other->{m_nStart});
    my $stop2  = _to_date ($TRUE, $other->{m_bStop}, $other->{m_nStop}, $other->{m_bStart}, $start2);

    # before/meets/left overlaps/left covers/covers (note the order is important)
    if ($start1 lt $start2)
    {
	if    ($stop1 lt $start2) { $bHowOverlaps = $ALLEN_BEFORE; }
	elsif ($stop1 eq $start2) { $bHowOverlaps = $ALLEN_MEETS; }       
	elsif ($stop1 lt $stop2)  { $bHowOverlaps = $ALLEN_LEFT_OVERLAPS; }
	elsif ($stop1 eq $stop2)  { $bHowOverlaps = $ALLEN_LEFT_COVERS; }	
	elsif ($stop1 gt $stop2)  { $bHowOverlaps = $ALLEN_COVERS; }
	else                      {} # do nothing
    }
    # starts/equals/right covers
    elsif ($start1 eq $start2)
    {
	if    ($stop1 lt $stop2)  { $bHowOverlaps = $ALLEN_STARTS; }
	elsif ($stop1 eq $stop2)  { $bHowOverlaps = $ALLEN_EQUALS; }
	elsif ($stop1 gt $stop2)  { $bHowOverlaps = $ALLEN_RIGHT_COVERS; }
	else                      {} # do nothing
    }
    # extends/after/during/finishes/right overlaps (note the order is important)
    elsif ($start1 gt $start2)
    {
	if    ($start1 eq $stop2) { $bHowOverlaps = $ALLEN_EXTENDS; }
	elsif ($start1 gt $stop2) { $bHowOverlaps = $ALLEN_AFTER; }
	elsif ($stop1  lt $stop2) { $bHowOverlaps = $ALLEN_DURING; }
	elsif ($stop1  eq $stop2) { $bHowOverlaps = $ALLEN_FINISHES; }
	elsif ($stop1  gt $stop2) { $bHowOverlaps = $ALLEN_RIGHT_OVERLAPS; }
	else                      {} # do nothing
    }  
    return $bHowOverlaps;
}

#-----------------------------------------------------------------------------
# Get how intervals overlap in Allen terminology
# Input:  <interval>
# Output: <Allen overlap type> string || FALSE
#-----------------------------------------------------------------------------

sub AllenHowOverlaps
{ 
    my $self  = shift;
    my $other = shift;
    my ($szOverlap) = ' does not overlap ';

    # If one of the intervals are empty AllenOverlap is undefined
    if ($self->{m_bEmpty} || $other->{m_bEmpty}) 
    { 
	print $self->get,  $szOverlap, $other->get, "\n";
	return $FALSE;
    }

    # Non-empty intervals
    my ($bOverlaps) = $self->_AllenOverlaps($other);

    if    ($bOverlaps == $ALLEN_BEFORE)         { $szOverlap = ' before '; }
    elsif ($bOverlaps == $ALLEN_MEETS)          { $szOverlap = ' meets '; }
    elsif ($bOverlaps == $ALLEN_LEFT_OVERLAPS)  { $szOverlap = ' left overlaps '; }
    elsif ($bOverlaps == $ALLEN_LEFT_COVERS)    { $szOverlap = ' left covers '; }
    elsif ($bOverlaps == $ALLEN_COVERS)         { $szOverlap = ' covers '; }
    elsif ($bOverlaps == $ALLEN_STARTS)         { $szOverlap = ' starts '; }
    elsif ($bOverlaps == $ALLEN_EQUALS)         { $szOverlap = ' equals '; }
    elsif ($bOverlaps == $ALLEN_RIGHT_COVERS)   { $szOverlap = ' right covers '; }
    elsif ($bOverlaps == $ALLEN_DURING)         { $szOverlap = ' during '; }
    elsif ($bOverlaps == $ALLEN_FINISHES)       { $szOverlap = ' finishes '; }
    elsif ($bOverlaps == $ALLEN_RIGHT_OVERLAPS) { $szOverlap = ' right overlaps '; }
    elsif ($bOverlaps == $ALLEN_EXTENDS)        { $szOverlap = ' extends '; }
    elsif ($bOverlaps == $ALLEN_AFTER)          { $szOverlap = ' after '; }
    print $self->get,  $szOverlap, $other->get, "\n";
}    

#-----------------------------------------------------------------------------
# Examines if intervals Allen before
# Input:  <interval>
# Output: boolean
#-----------------------------------------------------------------------------

sub AllenBefore
{
    my $self = shift; my $other = shift;
    $self->_AllenOverlaps ($other) == $ALLEN_BEFORE ? return $TRUE : return $FALSE;
}

#-----------------------------------------------------------------------------
# Examines if intervals Allen before
# Input:  <interval>
# Output: boolean
#-----------------------------------------------------------------------------

sub AllenMeets
{
    my $self = shift; my $other = shift;
    $self->_AllenOverlaps ($other) == $ALLEN_MEETS ? return $TRUE : return $FALSE;
}

#-----------------------------------------------------------------------------
# Examines if intervals Allen before
# Input:  <interval>
# Output: boolean
#-----------------------------------------------------------------------------

sub AllenLeftOverlaps
{
    my $self = shift; my $other = shift;
    $self->_AllenOverlaps ($other) == $ALLEN_LEFT_OVERLAPS ? return $TRUE : return $FALSE;
}

#-----------------------------------------------------------------------------
# Examines if intervals Allen left covers
# Input:  <interval>
# Output: boolean
#-----------------------------------------------------------------------------

sub AllenLeftCovers
{
    my $self = shift; my $other = shift;
    $self->_AllenOverlaps ($other) == $ALLEN_LEFT_COVERS ? return $TRUE : return $FALSE;
}

#-----------------------------------------------------------------------------
# Examines if intervals Allen covers
# Input:  <interval>
# Output: boolean
#-----------------------------------------------------------------------------

sub AllenCovers
{
    my $self = shift; my $other = shift;
    $self->_AllenOverlaps ($other) == $ALLEN_COVERS ? return $TRUE : return $FALSE;
}

#-----------------------------------------------------------------------------
# Examines if intervals Allen starts
# Input:  <interval>
# Output: boolean
#-----------------------------------------------------------------------------

sub AllenStarts
{
    my $self = shift; my $other = shift;
    $self->_AllenOverlaps ($other) == $ALLEN_STARTS ? return $TRUE : return $FALSE;
}

#-----------------------------------------------------------------------------
# Examines if intervals Allen equals
# Input:  <interval>
# Output: boolean
#-----------------------------------------------------------------------------

sub AllenEquals
{
    my $self = shift; my $other = shift;
    $self->_AllenOverlaps ($other) == $ALLEN_EQUALS ? return $TRUE : return $FALSE;
}

#-----------------------------------------------------------------------------
# Examines if intervals Allen right covers
# Input:  <interval>
# Output: boolean
#-----------------------------------------------------------------------------

sub AllenRightCovers
{
    my $self = shift; my $other = shift;
    $self->_AllenOverlaps ($other) == $ALLEN_RIGHT_COVERS ? return $TRUE : return $FALSE;
}

#-----------------------------------------------------------------------------
# Examines if intervals Allen during
# Input:  <interval>
# Output: boolean
#-----------------------------------------------------------------------------

sub AllenDuring
{
    my $self = shift; my $other = shift;
    $self->_AllenOverlaps ($other) == $ALLEN_DURING ? return $TRUE : return $FALSE;
}

#-----------------------------------------------------------------------------
# Examines if intervals Allen finishes
# Input:  <interval>
# Output: boolean
#-----------------------------------------------------------------------------

sub AllenFinishes
{
    my $self = shift; my $other = shift;
    $self->_AllenOverlaps ($other) == $ALLEN_FINISHES ? return $TRUE : return $FALSE;
}

#-----------------------------------------------------------------------------
# Examines if intervals Allen right overlaps
# Input:  <interval>
# Output: boolean
#-----------------------------------------------------------------------------

sub AllenRightOverlaps
{
    my $self = shift; my $other = shift;
    $self->_AllenOverlaps ($other) == $ALLEN_RIGHT_OVERLAPS ? return $TRUE : return $FALSE;
}

#-----------------------------------------------------------------------------
# Examines if intervals Allen extends
# Input:  <interval>
# Output: boolean
#-----------------------------------------------------------------------------

sub AllenExtends
{
    my $self = shift; my $other = shift;
    $self->_AllenOverlaps ($other) == $ALLEN_EXTENDS ? return $TRUE : return $FALSE;
}

#-----------------------------------------------------------------------------
# Examines if intervals Allen right overlaps
# Input:  <interval>
# Output: boolean
#-----------------------------------------------------------------------------

sub AllenAfter
{
    my $self = shift; my $other = shift;
    $self->_AllenOverlaps ($other) == $ALLEN_AFTER ? return $TRUE : return $FALSE;
}

##############################################################################
# Overloaded operators
##############################################################################

#-----------------------------------------------------------------------------
# If two intervals overlaps the union is returned
# Input:  <interval> <interval>
# Output: <interval> || undefined
#-----------------------------------------------------------------------------

sub _plus 
{
    my ($i1, $i2, $regular) = @_;
    my ($nMin, $nMax);
    $nMin = $nMax = 0;
    if ($i2->{m_bEmpty}) { return (ref $i1)->new ($i1->{m_nStart}, $i1->{m_nStop}) } 
    if ($i1->{m_bEmpty}) { return (ref $i2)->new ($i2->{m_nStart}, $i2->{m_nStop}) } 

    if ($i1->{m_bStart} == $RELATIVE || $i1->{m_bStop} == $RELATIVE ||
	$i2->{m_bStart} == $RELATIVE || $i2->{m_bStop} == $RELATIVE)
    {
	print STDERR "Sorry, + of relative intervals not implemented yet\n";
	return _new_empty Date::Interval;
    }

    if ($i1->overlaps ($i2))
    {
	$nMin = $i1->{m_nStart} lt $i2->{m_nStart} ? $i1->{m_nStart} : $i2->{m_nStart};
	$nMax = $i1->{m_nStop} gt $i2->{m_nStop}   ? $i1->{m_nStop}  : $i2->{m_nStop};
    }
    return (ref $i1)->new ($nMin, $nMax);
}

#-----------------------------------------------------------------------------
# If two intervals overlaps the union is returned
# Input:  <interval> <interval>
# Output: <interval> || undefined
#-----------------------------------------------------------------------------

sub _minus 
{
    my ($i1, $i2, $regular) = @_;
    my ($nStart, $nStop, $nLeft, $nRight);

    if ($i2->{m_bEmpty}) { return (ref $i1)->new ($i1->{m_nStart}, $i1->{m_nStop}); } 
    if ($i1->{m_bEmpty}) { return _new_empty Date::Interval; } 

    if ($i1->{m_bStart} == $RELATIVE || $i1->{m_bStop} == $RELATIVE ||
	$i2->{m_bStart} == $RELATIVE || $i2->{m_bStop} == $RELATIVE)
    {
	print STDERR "Sorry, + of relative intervals not implemented yet\n";
	return _new_empty Date::Interval;
    }

    my ($nOverlap) = $i1->_overlaps ($i2);
    $nStart = $nStop = 0;
    my ($bDefined) = $TRUE; # Used if temporal element should be returned

    if ($nOverlap == $MEETS)
    {
	$nStart = $i1->{m_nStart};
	$nStop  = $i1->{m_nStop};
	$nLeft = $i1->{m_nLeft};
	if ($i2->{m_nLeft} == $CLOSED) { $nRight = $OPEN; }
	else                           { $nRight = $i1->{m_nRight}; }
    }
    elsif ($nOverlap == $LEFT_OVERLAPS)
    {
	$nStart = $i1->{m_nStart};
	$nStop  = $i2->{m_nStart};
	$nLeft  = $i1->{m_nLeft};
	if ($i2->{m_nLeft} == $CLOSED) { $nRight = $OPEN; }
	else                           { $nRight = $CLOSED; }
    }
    elsif ($nOverlap == $RIGHT_OVERLAPS)
    {
	$nStart = $i2->{m_nStop};
	$nStop  = $i1->{m_nStop};
	if ($i2->{m_nRight} == $CLOSED) { $nLeft = $OPEN; }
	else                            { $nLeft = $CLOSED; }
	$nRight = $i1->{m_nRight};
    }
    elsif ($nOverlap == $TOTALLY_OVERLAPS)
    {
	print STDERR "Sorry minus and during overlap not implemented yet\n";
	$bDefined = $FALSE;
    }
    elsif ($nOverlap == $DURING)
    {
	$bDefined = $FALSE;
    }
    elsif ($nOverlap == $EXTENDS)
    {
	$nStart = $i1->{m_nStart};
	$nStop  = $i1->{m_nStop};
	if ($i2->{m_nRight} == $CLOSED) { $nLeft = $OPEN; }
	else                            { $nLeft = $i1->{m_nLeft}; }
	$nRight = $i1->{m_nRight};
    }

    else
    {
	# does not overlap
    }

    if ($bDefined)
    {
	my $int = new Date::Interval ($nStart, $nStop);
	$int->_setBrackets ($nLeft, $nRight);
	return $int;
    }
    else 
    {
	return _new_empty Date::Interval;
    }
}

#-----------------------------------------------------------------------------
# Operator <
# Input:  <interval> <interval>
# Output: boolean
#-----------------------------------------------------------------------------

sub _smaller_than
{
    my ($i1, $i2) = @_;
    if ($i1->{m_bEmpty} || $i2->{m_bEmpty}) { return $FALSE; }

    my $start1 = _to_date ($FALSE, $i1->{m_bStart}, $i1->{m_nStart});
    my $stop1  = _to_date ($TRUE, $i1->{m_bStop},  $i1->{m_nStop}, $i1->{m_bStart}, $start1);
    my $start2 = _to_date ($TRUE, $i2->{m_bStart}, $i2->{m_nStart});
    my $stop2  = _to_date ($TRUE, $i2->{m_bStop},  $i2->{m_nStop}, $i2->{m_bStart}, $start2);

    if ($stop1 lt $start2) { return $TRUE; }
    else                   { return $FALSE; }
}

#-----------------------------------------------------------------------------
# Operator >
# Input:  <interval> <interval>
# Output: boolean
#-----------------------------------------------------------------------------

sub _greater_than
{
    my ($i1, $i2) = @_;
    if ($i1->{m_bEmpty} || $i2->{m_bEmpty}) { return $FALSE; }

    my $start1 = _to_date ($FALSE, $i1->{m_bStart}, $i1->{m_nStart});
    my $stop1  = _to_date ($TRUE, $i1->{m_bStop},  $i1->{m_nStop}, $i1->{m_bStart}, $start1);
    my $start2 = _to_date ($TRUE, $i2->{m_bStart}, $i2->{m_nStart});
    my $stop2  = _to_date ($TRUE, $i2->{m_bStop},  $i2->{m_nStop}, $i2->{m_bStart}, $start2);

    if ($start1 gt $stop2) { return $TRUE; }
    else                   { return $FALSE; }
}

#-----------------------------------------------------------------------------
# Operator ==
# Input:  <interval> <interval>
# Output: boolean
#-----------------------------------------------------------------------------

sub _equal
{
    my ($i1, $i2) = @_;
    if ($i1->{m_bEmpty} || $i2->{m_bEmpty}) { return $FALSE; }

    my $start1 = _to_date ($FALSE, $i1->{m_bStart}, $i1->{m_nStart});
    my $stop1  = _to_date ($TRUE, $i1->{m_bStop},  $i1->{m_nStop}, $i1->{m_bStart}, $start1);
    my $start2 = _to_date ($TRUE, $i2->{m_bStart}, $i2->{m_nStart});
    my $stop2  = _to_date ($TRUE, $i2->{m_bStop},  $i2->{m_nStop}, $i2->{m_bStart}, $start2);

    if ($start1 eq $start2 && $stop1 eq $stop2) { return $TRUE;  }
    else                                        { return $FALSE; }
}

#-----------------------------------------------------------------------------
# Operator !=
# Input:  <interval> <interval>
# Output: boolean
#-----------------------------------------------------------------------------

sub _not_equal
{
    my ($i1, $i2) = @_;
    if ($i1->{m_bEmpty} || $i2->{m_bEmpty}) { return $FALSE; }

    my $start1 = _to_date ($FALSE, $i1->{m_bStart}, $i1->{m_nStart});
    my $stop1  = _to_date ($TRUE, $i1->{m_bStop},  $i1->{m_nStop}, $i1->{m_bStart}, $start1);
    my $start2 = _to_date ($TRUE, $i2->{m_bStart}, $i2->{m_nStart});
    my $stop2  = _to_date ($TRUE, $i2->{m_bStop},  $i2->{m_nStop}, $i2->{m_bStart}, $start2);

    if ($i1 == $i2) { return $FALSE; }
    else            { return $TRUE;  }
}

#-----------------------------------------------------------------------------
# Spaceship operator, used ONLY for sorting because based on the start value
# Input:  <interval> <interval>
# Output: -1 || 0 || 1
#-----------------------------------------------------------------------------

sub _spaceship 
{
    my ($i1, $i2) = @_;

    my $start1 = _to_date ($FALSE, $i1->{m_bStart}, $i1->{m_nStart});
    my $stop1  = _to_date ($TRUE, $i1->{m_bStop},  $i1->{m_nStop}, $i1->{m_bStart}, $start1);
    my $start2 = _to_date ($TRUE, $i2->{m_bStart}, $i2->{m_nStart});
    my $stop2  = _to_date ($TRUE, $i2->{m_bStop},  $i2->{m_nStop}, $i2->{m_bStart}, $start2);

    if    ($i1->{m_bEmpty})    { return -1; } # per definition :-)
    elsif ($i2->{m_bEmpty})    { return 1; }  # ditto
    elsif ($start1 eq $start2) { return 0; }
    elsif ($start1 lt $start2) { return -1; }
    elsif ($start1 gt $start2) { return 1; }
    else                       { print STDERR "Error in spaceship\n"; }
}

#------------------------------------------------------------------------------
# For strinifying an interval
# Input:  <interval>
# Output: string
#------------------------------------------------------------------------------

sub _stringify
{
    my $self = shift;
    return $self->get;
}

##############################################################################
# Various help functions
##############################################################################

#-----------------------------------------------------------------------------
# Converts a string to an <end point>
# Input:  string
# Output: <end point> <value type>
#-----------------------------------------------------------------------------

sub _getEndPoint
{
    my ($szEndPoint) = @_;
    
    # Is it a reference to a date?
    if (ref $szEndPoint)
    { 
	return ($szEndPoint, $ABSOLUTE);
    }
    # Is it a NOBIND and a NOW or a delta
    elsif ($szEndPoint =~ /^(\s*)NOBIND(\s*)(.*)/)  
    { 
	my $szRest = $3;
	if ($szRest =~ /NOW/) 
	{ 
	    return ('NOBIND NOW', $RELATIVE);
	}
	else
	{
	    # Can we parse up the delta?
	    my $delta = &ParseDateDelta ($szRest);
	    if (defined ($delta))
	    {
		return ($szRest,  $RELATIVE);
	    }
	}
    }
    # Is it a string specifying a date
    else
    {
	my $date = &ParseDate ($szEndPoint); 
	if (defined ($date))
	{
	    return ($date, $ABSOLUTE); 
	}
    }
    return ('', ''); # An error
}

#-----------------------------------------------------------------------------
# Convert <end point> to a date
# Input:  <fix clock> <value type> <end point> [<start date value type> <start date>]
# Output: <date>
#-----------------------------------------------------------------------------

sub _to_date
{
    my ($bFixClock, $nValueType, $szEndPoint, $nStartValueType, $dStartDate) = @_;
    my ($dDate);

    if($nValueType == $RELATIVE) 
    {
	if ($szEndPoint eq 'NOBIND NOW') # NOW
	{ 
	    $dDate = &_getCurrentTime ($bFixClock);
	} 
	else  # a delta
	{
	    # use dStartDate as outset for delta
	    if (defined($dStartDate) && $nStartValueType == $ABSOLUTE)
	    {
		$dDate = &DateCalc ($dStartDate, $szEndPoint);
	    }
	    else                      # use NOW as outset for delta
	    {
		$dDate = &DateCalc (&_getCurrentTime ($bFixClock), $szEndPoint);
	    }
	}             
    }
    elsif ($nValueType == $ABSOLUTE) 
    {
	$dDate = $szEndPoint;
    }
    else
    {
	print STDERR "ERROR: Wrong <value type> $nValueType\n";
    }
    return $dDate;
}

#-----------------------------------------------------------------------------
# Converst and <end point> to a string
# Input:   boolean
# Output:  string
#-----------------------------------------------------------------------------

sub _getCurrentTime
{
    my($bFixClock) = @_;
    if (!$bFixClock)  { $Now = &ParseDate ('today');  }
    return $Now;
}

#-----------------------------------------------------------------------------
# Converts and <end point> to a string
# Input:   <value type> <end point>
# Output:  string
#-----------------------------------------------------------------------------

sub _to_string
{
    my ($nValueType, $szEndPoint) = @_;
    my ($szResult);

    if ($nValueType == $ABSOLUTE)
    {
	$szResult = &UnixDate ($szEndPoint, $DisplayFormat);
    }
    elsif ($nValueType == $RELATIVE)
    {
	if ($szEndPoint eq 'NOBIND NOW') { $szResult = 'now'; }
	else                             { $szResult = $szEndPoint; }
    }
    else
    {
	print STDERR "ERROR wrong <value type> $nValueType in _to_string\n";
    }
    return $szResult;
}

1;

__END__

##############################################################################
##############################################################################
# POD
##############################################################################
##############################################################################

=head1 NAME

Date::Interval - handling of temporal intervals based on Date::Manip

=head1 SYNOPSIS

    use Date::Interval;

    ### class methods ###
    Date::Interval->setDefaultIntervalType ($Date::Interval::OPEN_INT); 
    $int_open = new Date::Interval ("10-10-1997", "10-20-1997"); 
    print "$int_open\n"        # prints  '(10-10-1997, 10-20-1997) 

    $nDefaultType = Date::Interval->getDefaultIntervalType;

    ### constructor ##
    $i1 = new Date::Interval ("10-30-1997", "12-01-1998");
    $i2 = new Date::Interval ("01-20-1996", "11-01-1997", $Date::Interval::RIGHT_OPEN_INT);

    use Date::Manip;
    $date1 = &ParseDate ("10-10-1997");
    $date2 = &ParseDate ("10-15-1997");
    $int = new Date::Interval ($d1, $d2);

    ### Overload operators ###
    $i3 = $i1 + $i2;          # + gives the sum of intervals if the overlap
    print "$i3\n";            # prints '[01-20-1997, 12-01-1998)'

    $i4 = $i1 - $i2;          # - gives difference of intervals of intervals
    print "$i4\n";            # prints '[11-01-1997, 12-01-1998)'
   
    $i5 = $i1 - $i1; 
    print "$i5\n";            # prints '<empty>'

    ### <Allen overlap type> ### 
    $X = new Date::Interval (<parameters>);
    $Y = new Date::Interval (<parameters>);
                              ###  relationship between intervals ###
    $Y->AllenBefore ($X);             YYYYYY XXXXXX

    $Y->AllenMeets ($X);              YYYYYYXXXXXX

    $Y->AllenLeftOverlaps ($X);          XXXXXX
                                      YYYYYY

    $Y->AllenLeftCovers ($X);            XXXXXX
                                      YYYYYYYYY

    $Y->AllenCovers ($X);                XXXXXX
                                      YYYYYYYYYYYY

    $Y->AllenStarts ($X);             XXXXXX
                                      YYY

    $Y->AllenEquals ($X);             XXXXXX
                                      YYYYYY
    
    $Y->AllenRightCovers ($X);        XXXXXX
                                      YYYYYYYYY

    $Y->AllenDuring ($X);             XXXXXX
                                       YYYY

    $Y->AllenFinishes ($X);           XXXXXX
				        YYYY 

    $Y->AllenRightOverlaps ($X);      XXXXXX
                                         YYYYYY

    $Y->AllenExtends ($X);            XXXXXXYYYYYY

    $Y->AllenAfter ($X):              XXXXXX YYYYYY

    ### <overlap type> ###
    $Y->before ($X)         same as  $Y->AllenBefore ($X)
    $Y->meets  ($X)         same as  $Y->AllenMeets ($X)

    $Y->leftOverlaps ($X)   same as  $Y->AllenLeftOverlaps ($X)  or
                                     $Y->AllenStarts ($X)

    $Y->totalOverlaps ($X)  same as  $Y->AllenCovers ($X)        or
                                     $Y->AllenLeftCovers ($X)    or
                                     $Y->AllenRightCovers ($X)   or
                                     $Y->AllenEquals ($X)

    $Y->rightOverlaps ($X)  same as  $Y->AllenFinishes ($X)      or
                                     $Y->AllenRightCovers

    $Y->during ($X)         same as  $Y->AllenDuring ($X)
    $Y->extends ($X)        same as  $Y->AllenExtends ($X)
    $Y->after ($X)          same as  $Y->AllenAfter ($X)

    ### <interval type> ###
    $closed_int = new Interval ("10-10-1997", "10-20-1997", $CLOSED_INT); 
    print "$closed_int\n";      # prints [10-10-1997, 10-20-1997]

    $left_open_int = new Interval ("10-10-1997", "10-20-1997", $LEFT_OPEN_INT); 
    print "$left_open_int\n";   # prints (10-10-1997, 10-20-1997]

    $right_open_int = new Interval ("10-10-1997", "10-20-1997", $RIGHT_OPEN_INT); 
    print "$right_open_int\n";  # prints [10-10-1997, 10-20-1997)

   $open_int = new Interval ("10-10-1997", "10-20-1997", $OPEN_INT); 
   print "$open_int\n";         # prints (10-10-1997, 10-20-1997)

   ### check and get overlapping interval ###
    $i1 = new Interval ("10-30-1997", "12-01-1998");
    $i2 = new Interval ("01-20-1996", "11-01-1997");
    $i3 = new Interval ("01-01-1995", "04-30-1995");

    if ($i1->overlaps ($i2)) {
        $i4 = $i1->getOverlap($i2);
        print "$i4\n";              # prints [10-30-1997, 11-01-1997)
    }
    if ($i1->overlaps ($i3)){       # tests fails, does not print anything
        $i5 = $i1->getOverlap($i2);
        print "$i5\n";
    }

=head1 DESCRIPTION

    All strings which can be used to create a Date::Manip date object
    can be used to create an Interval. However, the start date must be
    greater than the stop date. Because Date::Manip both handles dates
    and times this module can also handle both dates and times.

    The comparison of intervals is based on the 13 ways intervals can
    overlap as defined by J.F. Allen (See the litteratur). Further, I
    have included a small number of interval comparison which are
    handy if you are only interested in getting the overlapping region
    of two intervals.

=head2 Open and Closed Intervals

    A closed interval is closed in an interval where both the start
    and the stop values are included in the interval. As an example
    [10-10-1997, 10-30-1997] both the 10th and the 30th of November is
    a part of the interval.

    An open interval is an interval where the start value or the stop
    value are not included in the interval. In the right open interval
    [10-10-1997, 10-30-1997) the 10th of November is a part of the
    interval but the 30th of November is not. 

    There are three types of open intervals
    - right open intervals, e.g., [10-10-1997, 10-30-1997)
    - left open intervals, e.g., (10-10-1997, 10-30-1997]
    - open intervals, e.g., (10-10-1997, 10-30-1997)

=head2 Absolute and Relative Intervals 

    An absolute interval is an interval where the start and the stop
    values of the inteval are anchored on the time line, i.e., they
    are specific dates as 04-30-1994.

    A relative interval is an interval where the start or the stop
    value is not anchored on the time line, e.g., 'tomorrow'. When
    'tomorrow' evaluated now it has one value when evaluated a month
    from now it has a different values.

    Date::Interval fully supports absolute intervals and to a limited
    degree relative intervals. 

    The relative intervals supported currently (NOW :-)) are of the
    following type.

    $int1 = new Date::Interval("10-21-1997", 'NOBIND NOW');

    Relative start and stop values are prefixed with the word
    'NOBIND'. In the example 'NOBIND NOW' means that the current time
    (now) whenever it asked for. So if you ask for the length of $int1
    at the 24th of October you get 3 days. If you ask for the length
    of $int1 again at the 28th of October you get 7 days.

    I am working on additional support for relative Intervals.

=head2 Defaults 

    The default interval type is right open intervals. Stick to this
    interval type if you want to keep life simple.

    To use Date::Manip the time zone variable must be set. It is
    default set to Central European Time (CET). For Americans, this is
    the Capital of Stockholm :-).

    To change the time zone, e.g., to Eastern Standard Time (EST) put
    in our script $Date::Manip::TZ = 'EST'; (As an European I assume
    this must be close to Atlanta, New Mexico).

    The default input format is default of Date::Manip, that is
    "10-12-1997" is the 12th of October 1997 not the 10th of December
    1997. To change the input format, e.g., put in our script
    &Date::Manip::Date_Init("DateFormat=non-US");

    The default output format is MM-DD-YYY. It Can be changed by
    calling Interval->setDisplayFormat(<string>). Where <string> is
    a UnixDate format in Date::Manip.

    The default separator when an interval is printed is the special
    variable $, $OUTPUT_FIELD_SEPARATOR. If this value is not defined
    ',' is used.

=head2 The "Fixed" Clock

    The module has a class variable $NOW which contains the current
    time. The current time must be fixed when relative intervals are
    compared, otherwise the comparison may return the wrong result. As
    an example if the two intervals [NOBIND NOW, NOBIND NOW) [NOBIND
    NOW, NOBIND NOW) are compared for equality the result is
    true. However, if the equality comparison is implemented by asking
    four time for the current time the times returned may be different
    because the *real world clock* ticks between the invocations of
    getting the current time. If the clock ticks the equality
    predicate in the example returns false.

    Because different interval objects must be compared with the same
    clock the variable must be a class variable and not an instance
    variable. $NOW is used in the method _to_date.

=head2 "Non-terminals" used in the Source Code

=over 4

=item   
    <delta>              ::= Date::Manip delta data type

=item 
    <date>               ::= Date::Manip data type

=item 
    <interval end>       ::= CLOSE || OPEN

=item 
    <interval type>      ::= CLOSED_INT || OPEN_INT || LEFT_OPEN_INT || RIGHT_OPEN_INT

=item 
    <value type>         ::= ABSOLUTE || RELATIVE

=item 
    <overlap type>       ::= How two intervals overlaps

=item 
    <Allen overlap type> ::= How two intervals Allen overlaps

=back


=head1 BUGS

    Tried my best to avoid them send me an email if you are bitten by
    a bug. 

    Note, the module cannot handle subtract intervals which overlap
    with "during" overlaps, this results in two intervals (currently
    results in an empty interval)

=head1 TODO 

    - Cannot take references to dates as input parameters for the
      constructors

    - Cannot subtract intervals which overlap with "during" overlaps,
      this results in two intervals (currently results an error message and
      an empty interval is returned)

    - Implement getOverlap and overloaded operators for relative intervals

=head1 Change History

    ### Changes version 0.01 => 0.02 ###
    - Add overload  <, >, ==, !=, <=>. 
    - Add stringLength, to print length of interval in a more readable way.
    - Changed the default separator to the $, special variable
    - Added support for comparison of relative intervals 

    Changes thanks to Tim Bruce
    - Changed the module name from Interval to Date::Interval
    - Added methods getStart and getStop.
    - Added method lengthString to print nicely the length of the
      interval.
    - Changed the default output format to be similar to the 
      default input format
    - Taken BEGIN {$Date::Manip::TZ = "CET"; &Date_Init ("DateFormat=non-US");}
      out because it is anti-social :-)
    - Added to POD that the both dates and times can be used with intervals
    - Added to POD the description of open and closed intervals

=head1 LITTERATURE

    Allen, J. F., "An Interval-Based Representation of Temporal Knowledge",
    Communication of the ACM, 26(11) pp. 832-843, November 1983.

=head1 AUTHOR

Kristian Torp <F<torp@cs.auc.dk>>

=cut

#eof
