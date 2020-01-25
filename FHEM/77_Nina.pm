####################################################################################################
#
#  77_Nina.pm
#
#  (c) 2019 Kölnsolar
#
#  Special thanks goes to comitters:
#       - Marko Oldenburg (leongaultier at gmail dot com)
#       - herrmannj (message filter by geographical base longitude/latitude + distance
#  Storm warnings from unwetterzentrale.de
#  inspired by 77_UWZ.pm
#
#  Copyright notice
#
#  This script is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  (at your option) any later version.
#
#  The GNU General Public License can be found at
#  http://www.gnu.org/copyleft/gpl.html.
#  A copy is found in the text file GPL.txt and important notices to the license
#  from the author is found in LICENSE.txt distributed with these scripts.
#
#  This script is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  This copyright notice MUST APPEAR in all copies of the script!
#
#  +*00:00:05 {fhem("define Nina_device Nina DE 50997 1200")}
# keine korrekte Neuanlage bei defmod(bsp. URL)
#
#  $Id: 77_Nina.pm 17646 2020-01-21 11:20:16Z Kölnsolar $
#
####################################################################################################
# also a thanks goes to hexenmeister
##############################################



package main;
use strict;
use feature qw/say switch/;
use warnings;
no if $] >= 5.017011, warnings => 'experimental::lexical_subs','experimental::smartmatch';

my $missingModul;

eval "use JSON;1" or $missingModul .= "JSON ";
eval "use Encode::Guess;1" or $missingModul .= "Encode::Guess ";

require 'Blocking.pm';
use HttpUtils;

use vars qw($readingFnAttributes);
use vars qw(%defs);

my @DEweekdays = qw(Sonntag Montag Dienstag Mittwoch Donnerstag Freitag Samstag);
my @DEmonths = ( "Januar","Februar","MÃ¤rz","April","Mai","Juni","Juli","August","September","Oktober","November","Dezember");
my @ENweekdays = qw(sunday monday thuesday wednesday thursday friday saturday);
my @ENmonths = ("January","February","March","April","MÃ¤y","June","July","August","September","October","November","December");
my @NLweekdays = qw(zondag maandag dinsdag woensdag donderdag vrijdag zaterdag);
my @NLmonths   = ("januari","februari","maart","april","mei","juni","juli","augustus","september","oktober","november","december");
my @FRweekdays = qw(dimanche lundi mardi mercredi jeudi vendredi samedi);
my @FRmonths   = ("janvier","fÃ©vrier","mars","avril","mai","juin","juillet","aoÃ»t","september","octobre","novembre","decembre");

my $MODUL           = "Nina";
my $version         = "0.3.0";

# Declare functions
sub Nina_Log($$$);

#my $countrycode = "DE";
#my $geocode = "05315";
#my $Nina_alert_url = "http://feed.alertspro.meteogroup.com/AlertsPro/AlertsProPollService.php?method=getWarning&language=de&areaID=UWZ" . $countrycode . $geocode;

sub Nina_Initialize($) {

    my ($hash) = @_;
    $hash->{DefFn}    = "Nina_Define";
    $hash->{UndefFn}  = "Nina_Undef";
    $hash->{SetFn}    = "Nina_Set";
#    $hash->{GetFn}    = "Nina_Get";
    $hash->{AttrList} = "disableDWD:0,1 ".
			"disableLHP:0,1 ".
			"distance:selectnumbers,0,1,99,0,lin ".
                        "htmlattr ".
                        "htmltitle ".
                        "htmltitleclass ".
                        "htmlsequence:ascending,descending ".
                        "latitude ".
                        "longitude ".
                        "sort_readings_by:distance,creation,severity ".
                        "intervalAtWarnLevel ".
                        "disable:1 ".
                        $readingFnAttributes;
   
    foreach my $d(sort keys %{$modules{Nina}{defptr}}) {
        my $hash = $modules{Nina}{defptr}{$d};
        $hash->{VERSION}      = $version;
    }
}

###################################
sub Nina_Define($$) {

    my ( $hash, $def ) = @_;
    my $name = $hash->{NAME};
    my $lang = "";
    my @a    = split( "[ \t][ \t]*", $def );
   
    return "Error: Perl moduls ".$missingModul."are missing on this system" if( $missingModul );
    return "Wrong syntax: use define <name> Nina <CountryCode> <Interval> "  if (int(@a) != 4 and  ((lc $a[2]) ne "search"));

    if ((lc $a[2]) ne "search") {

        $hash->{STATE}           = "Initializing";
        $hash->{CountryCode}     = $a[2];
        
        ## URL by CountryCode

        my $URL_language="en";
        if ( $hash->{CountryCode} ~~ [ 'DE' ] ) {
            $URL_language="de";
        }
        
#        $hash->{URL} =  "http://feed.alertspro.meteogroup.com/AlertsPro/AlertsProPollService.php?method=getWarning&language=" . $URL_language . "&areaID=UWZ" . $a[2] . $a[3];
        $hash->{URL} =  "	";    
        
        $hash->{fhem}{LOCAL}    = 0;
        $hash->{INTERVAL}       = $a[3];
        $hash->{INTERVALWARN}   = 0;
        $hash->{VERSION}        = $version;
       
        RemoveInternalTimer($hash);
       
        #Get first data after 12 seconds
        InternalTimer( gettimeofday() + 12, "Nina_Start", $hash, 0 );

    }
    
#    $modules{Nina}{defptr}{$hash->{geocode}} = $hash;
    
    return undef;
}

#####################################
sub Nina_Undef($$) {

    my ( $hash, $arg ) = @_;

    RemoveInternalTimer( $hash );
    BlockingKill( $hash->{helper}{RUNNING_PID} ) if ( defined( $hash->{helper}{RUNNING_PID} ) );
    
    delete($modules{Nina}{defptr}{$hash->{geocode}});
    
    return undef;
}

#####################################
sub Nina_Set($@) {

    my ( $hash, @a ) = @_;
    my $name    = $hash->{NAME};
    my $reUINT = '^([\\+]?\\d+)$';
    my $usage   = "Unknown argument $a[1], choose one of update:noArg ";

    return $usage if ( @a < 2 );

    my $cmd = lc( $a[1] );
    
    given ($cmd)
    {
        when ("?")
        {
            return $usage;
        }
        
        when ("update")
        {
            Nina_Log $hash, 4, "set command: " . $a[1];
            $hash->{fhem}{LOCAL} = 1;
            Nina_Start($hash);
            $hash->{fhem}{LOCAL} = 0;
        }
        
        default
        {
            return $usage;
        }
    }
    
    return;
}

#sub Nina_Get($@) {
#
#    my ( $hash, @a ) = @_;
#    my $name    = $hash->{NAME};
#   
#    if ( $hash->{CountryCode} ~~ [ 'DE' ] ) {
#        my $usage   = "Unknown argument $a[1], choose one of  ";
#        return $usage if ( @a < 2 );
#       
#    }
#}


#####################################
sub Nina_Start($) {

    my ($hash) = @_;
    my $name   = $hash->{NAME};
   
    return unless (defined($hash->{NAME}));
   
    if(!$hash->{fhem}{LOCAL} && $hash->{INTERVAL} > 0) {        # set up timer if automatically call
        RemoveInternalTimer( $hash );
        InternalTimer(gettimeofday() + $hash->{INTERVAL}, "Nina_Start", $hash, 1 );
        return undef if( IsDisabled($name) );
        readingsSingleUpdate($hash,'currentIntervalMode','normal',0);
    }

    ## URL by CountryCode
    my $URL_language="en";
#    if (AttrVal($hash->{NAME}, "lang", undef) ) {  
#        $URL_language=AttrVal($hash->{NAME}, "lang", "");
#    } else {
        if ( $hash->{CountryCode} ~~ [ 'DE' ] ) {
            $URL_language="de";
        }
#    }

    $hash->{URL} =  "https://warnung.bund.de/bbk.mowas/gefahrendurchsagen.json";
    
   
    if ( not defined( $hash->{URL} ) ) {
        Nina_Log $hash, 3, "missing URL";
        return;
    }
  
    $hash->{helper}{RUNNING_PID} = BlockingCall( 
			            "Nina_Run",          # callback worker task
			            $name,              # name of the device
			            "Nina_Done",         # callback result method
			            120,                # timeout seconds
			            "Nina_Aborted",      #  callback for abortion
			            $hash );            # parameter for abortion
}


#####################################
sub Nina_Run($) {

    my ($name) = @_;
    my $ptext=$name;
    my $message;
    my $i=0;    # counter for filtered messages
    
    return unless ( defined($name) );
   
    my $hash = $defs{$name};
    return unless (defined($hash->{NAME}));
    
    my $readingStartTime = time();

    my ($Nina_warnings, @Nina_records, $enc) = "";
   
    my %warnlevel = ( "Minor" => "1",
		      "Moderate" => "2",
                      "Severe" => "3",
                      "Extreme" => "4");

    # acquire the json-response
    my $response = Nina_JSONAcquire($hash,$hash->{URL}); 					     # MoWaS-Meldungen
    if (substr($response,0,5) ne "Error") {
    Nina_Log $hash, 5, length($response)." characters captured from Nina:  ".$response;
    $Nina_warnings = JSON->new->ascii->decode($response);
    @Nina_records = @{$Nina_warnings};
    }
    else {
	$message .= $response;
    }

    $response = Nina_JSONAcquire($hash,"https://warnung.bund.de/bbk.katwarn/warnmeldungen.json"); 	# Katwarn-Meldungen
    if (substr($response,0,5) ne "Error") {
    Nina_Log $hash, 5, length($response)." characters captured from Katwarn:  ".$response;
    $Nina_warnings = JSON->new->ascii->decode($response);
   foreach my $element (@{$Nina_warnings}) {
        push @Nina_records, $element;
    }
    }
    else {
	$message .= $response;
    } 

    $response = Nina_JSONAcquire($hash,"https://warnung.bund.de/bbk.biwapp/warnmeldungen.json"); 	# BIWAPP-Meldungen
    	$response =~ s/\\u/ /g; 
    if (substr($response,0,5) ne "Error") {
    Nina_Log $hash, 5, length($response)." characters captured from BIWAPP:  ".$response;
    $Nina_warnings = JSON->new->ascii->decode($response);
   foreach my $element (@{$Nina_warnings}) {
        push @Nina_records, $element;
    }
    }
    else {
	$message .= $response;
    } 

    if(!AttrVal($name,"disableDWD",0)) {
    $response = Nina_JSONAcquire($hash,"https://warnung.bund.de/bbk.dwd/unwetter.json"); 	# DWD-Meldungen
#    	$response =~ s/\\u/ /g; 
    if (substr($response,0,5) ne "Error") {
    Nina_Log $hash, 5, length($response)." characters captured from DWD:  ".$response;
#    $Nina_warnings = JSON->new->ascii->decode($response);  #'"' expected, at character offset 2 (before "(end of string)") 
eval {
      $Nina_warnings = JSON->new->ascii->decode($response);
	1;
} or do {
  my $e = $@;
    Nina_Log $hash, 5, " malformed JSON. decode returns: ".$e." server-response was: ".$response;
};   foreach my $element (@{$Nina_warnings}) {
        push @Nina_records, $element;
    }
    }
    else {
	$message .= $response;
    }
    }
    if(!AttrVal($name,"disableLHP",0)) { 
    $response = Nina_JSONAcquire($hash,"https://warnung.bund.de/bbk.lhp/hochwassermeldungen.json"); 	# Hochwasser-Meldungen
#    	$response =~ s/\\u/ /g; 
    if (substr($response,0,5) ne "Error") {
    Nina_Log $hash, 5, length($response)." characters captured from HWZ:  ".$response;
    $Nina_warnings = JSON->new->ascii->decode($response);  
   foreach my $element (@{$Nina_warnings}) {
        push @Nina_records, $element;
    }
    }
    else {
	$message .= $response;
    }
    } 
    return "$name|$message" if (defined($message));
     $Nina_warnings = \@Nina_records;
#     @Nina_records;
      HttpUtils_Close( $hash->{helper}{httpref});
      $hash->{helper}{httpref} = "";

#use Data::Dumper;
#    Nina_Log $hash, 5, "Nina after decoding ".Dumper($Nina_warnings);
#    print "All warnings after decoding ".@Nina_records;
     $enc = guess_encoding($Nina_warnings);
#    Nina_Log $hash, 5, "Nina $enc";

    my $Nina_warncount = scalar(@{$Nina_warnings});
    Nina_Log $hash, 4, "There are $Nina_warncount warning records active";
    
    my %typenames       = ( "1" => "unknown",     # <===== FIX HERE
                            "2" => "sturm", 
                            "11" => "temperatur" ); # 11 = bodenfrost

    my %typenames_de_str= ( "1" => "unknown",     # <===== FIX HERE
                             "11" => "Bodenfrost" ); # 11 = bodenfrost

    my %typenames_en_str= ( "1" => "unknown",     # <===== FIX HERE
                            "11" => "soil frost" ); # 11 = bodenfrost
                    
    my %severitycolor   = ( "0" => "green", 
                            "1" => "unknown", # <===== FIX HERE
                            "2" => "unknown", # <===== FIX HERE
                            "3" => "unknown", # <===== FIX HERE
                            "4" => "orange",
                            "5" => "unknown", # <===== FIX HERE
                            "6" => "unknown", # <===== FIX HERE
                            "7" => "orange",
                            "8" => "gelb",
                            "9" => "gelb", # <===== FIX HERE
                            "10" => "orange",
                            "11" => "rot",
                            "12" => "violett" );


    my (@Ninamaxlevel, @Nina_filtered_records, $latitude, $longitude);
    my ($new_warnings_count,$warnings_in_area)  = (0,0);

    $latitude  = AttrVal($name, "latitude", AttrVal("global", "latitude", 0));
    $longitude = AttrVal($name, "longitude", AttrVal("global", "longitude", 0));

Nina_Log $hash, 4, "Start Loop of record selection: latitude=$latitude, longitude=$longitude";
    foreach my $single_warning (@{$Nina_warnings}) {
		my ($ii, $flag_warning_in_area)  = (0,0,);# $ii counter for area array
		Nina_Log $hash, 4, "Record with sender: ".$single_warning->{'sender'};
		while(defined($single_warning->{'info'}[0]{'area'}[$ii])) {
			Nina_Log $hash, 4, "       Record with geocode: ".$single_warning->{'info'}[0]{'area'}[$ii]{'geocode'}[0]{'valueName'};
			my $iii = 0;  # counter for polygon array within area array
			while(defined($single_warning->{'info'}[0]{'area'}[$ii]{'polygon'}[$iii]) && !$flag_warning_in_area) {
				Nina_Log $hash, 5, "       Record with polygon: ".$single_warning->{'info'}[0]{'area'}[$ii]{'polygon'}[$iii];
				my ($res,$dist)= (Nina_IsInArea($hash,$latitude,$longitude, $single_warning->{'info'}[0]{'area'}[$ii]{'polygon'}[$iii]));
				if ($res) {
				   $warnings_in_area++;
				   $flag_warning_in_area = 1;
				   Nina_Log $hash, 4, "       warning in area";
				   $single_warning->{'distance'} = 0;
				   $single_warning->{'area'} = $ii;
				}
				else {
				   if ($dist > 0 && $dist < AttrVal( $name, 'distance',0 ) ) { 
					Nina_Log $hash, 4, "       warning in distance of $dist km";
					if(!defined($single_warning->{'distance'}) || defined($single_warning->{'distance'}) && $dist < $single_warning->{'distance'})  { # || $single_warning->{'distance'} == 0);
					   $single_warning->{'distance'} = $dist;
					   $single_warning->{'area'} = $ii;
				   	}
				   }
				}
				$iii++;
			}
#	Nina_Log $hash, 3, "Severity Nina: $single_warning->{'info'}[0]{'severity'} for $single_warning->{'info'}[0]{'area'}[$ii]{'areaDesc'}" if (defined($single_warning->{'info'}[0]{'severity'}) && $single_warning->{'info'}[0]{'severity'} ne "Minor" && defined($single_warning->{'sender'}) && substr($single_warning->{'sender'},4,3) ne "dwd"); 
			$ii++;
		}
		if ($flag_warning_in_area || defined($single_warning->{'distance'})) {
		  $single_warning->{'sent'} = $single_warning->{'info'}[0]{'onset'} if (defined($single_warning->{'info'}[0]{'onset'}));
		  $single_warning->{'severity_sort'} =  $warnlevel{$single_warning->{'info'}[0]{'severity'}};
        	  push @Nina_filtered_records, $single_warning;		   
#		   $message .= Nina_preparemessage($hash,$single_warning,$i,$single_warning->{'area'},$single_warning->{'distance'}) ;
		   $i++;
        }
    }

    my $sortby = AttrVal( $name, 'sort_readings_by',"" );
    my @sorted;

    if ( $sortby eq "creation" ) {
        Nina_Log $hash, 4, "Sorting by creation";
        @sorted =  sort { $b->{sent} cmp $a->{sent} } @Nina_filtered_records;
    } elsif ( $sortby eq "severity" ) {
        Nina_Log $hash, 4, "Sorting by severity";
        @sorted =  sort { $b->{severity_sort} <=> $a->{severity_sort} } @Nina_filtered_records;
    } else {
        Nina_Log $hash, 4, "Sorting by distance";
        @sorted =  sort { $a->{distance} <=> $b->{distance} } @Nina_filtered_records;
    }

$i = 0;
    foreach my $single_warning (@sorted) {
       $message .= Nina_preparemessage($hash,$single_warning,$i,$single_warning->{'area'},$single_warning->{'distance'}) if($i < 30);
$i++;
    }    

    $message .= "durationFetchReadings|";
    $message .= sprintf "%.2f",  time() - $readingStartTime;
    $message =~ s/\n/ /g; 
    $message .= "|WarnCount|$i|WarnCountInArea|$warnings_in_area";

    Nina_Log $hash, 3, "Done fetching data with ".$i." warnings active";
    Nina_Log $hash, 4, "Will return : "."$name|$message" ;
    
    return "$name|$message" ;
}

#####################################
# asyncronous callback by blocking
sub Nina_Done($) {
    Nina_Log "Nina", 5, "Beginning processing of selected data.";
    my ($string) = @_;
    return unless ( defined($string) );
   
    my %warnlevel = ( "Minor" => "1",
		      "Moderate" => "2",
                      "Severe" => "3",
                      "Extreme" => "4");

    # all term are separated by "|" , the first is the name of the instance
    my ( $name, %values ) = split( "\\|", $string );
    my $hash = $defs{$name};
    return unless ( defined($hash->{NAME}) );
 
    my $max_level = 0;  
    
    # UnWetterdaten speichern
    readingsBeginUpdate($hash);
    Nina_Log $hash, 5, "Starting Readings Update.";

    my $readingspec= "";

    if ( defined $values{Error} ) {
        readingsBulkUpdateIfChanged( $hash, "lastConnection", $values{Error} );
    } else {
	my $new_warnings_count  = 0;  # new reading NewWarnings
	while (my ($rName, $rValue) = each(%values) ) {
	   if ($rName =~ m/_EventID/) {
		  if (ReadingsVal($name, $rName, 0) ne $rValue) {
			  $new_warnings_count++;  # new readings counter
			  my $message = Nina_deletewarning($hash,"^Warn_". substr($rName,5,2).'_.*$');
			  if ($message) {
				  Nina_Log $hash, 4, "Delete old warning before rewrite"; 
				  Nina_Log $hash, 5, $message;
			  }
		  }
	   }
	}
    while (my ($rName, $rValue) = each(%values) ) {
	    if ($rName ne "WarnCount" && $rName ne "WarnCountInArea") {
	       if ($rName =~ m/_EventID/) {
              readingsBulkUpdateIfChanged( $hash, $rName, $rValue,1 );    # update of reading with event for _EventID, if changed
	       }
	       else {
#	           if ($rName =~ m/_Level/) {
#		     $max_level = $rValue if ($rValue gt $max_level );  # max level of warnings
	           if ($rName =~ m/_Severity/) {
		     my $severity = $warnlevel{$rValue} ;
		     $max_level = $severity if (defined($severity) && $severity gt $max_level );  # max level of warnings
               	   }
                  readingsBulkUpdateIfChanged( $hash, $rName, $rValue,0 );    # update of reading if changed w/o event
               }
            }
	    else {
               readingsBulkUpdateIfChanged( $hash, $rName, $rValue,1 );    # update of reading if changed with event only for selected("header") readings
            }
            Nina_Log $hash, 5, "reading:$rName value:$rValue";
        }
        if (keys %values > 0) {
            my $newState;
            Nina_Log $hash, 4, "Delete old warnings"; 
            for my $Counter ($values{WarnCount} .. 29) {
		my $param = "";        
 if ($Counter < 10) {$param = "^Warn_0${Counter}_.*".'$';}
 else { $param = "^Warn_${Counter}_.*".'$';}
		 my $message = Nina_deletewarning($hash,$param);
		 Nina_Log $hash, 5, $message if ($message);
	    }
            if (defined $values{WarnCount}) {
                # Message by CountryCode
                $newState = "Warnings: " . $values{WarnCount}." in local area: " . $values{WarnCountInArea};
                $newState = "Warnungen: " . $values{WarnCount}." Lokal: " . $values{WarnCountInArea} if ( $hash->{CountryCode} ~~ [ 'DE' ] );
                # end Message by CountryCode
            } else {
                $newState = "Error: Could not capture all data. Please check CountryCode and geocode.";
            }
  #          readingsBulkUpdateIfChanged($hash, "WarnLevelMax", $max_level,1 );    # update of reading only if changed
            readingsBulkUpdate($hash, "WarnLevelMax", $max_level,1 );    # update of reading and event for each cycle
	    if ($new_warnings_count > 0) {
         	readingsBulkUpdate($hash, "NewWarnings", $new_warnings_count,1);    # update of reading and event, if new warnings are detected
            }
	    else {
         	readingsBulkUpdateIfChanged($hash, "NewWarnings", $new_warnings_count,1); # update of reading and event only, if changed to 0
            }
            readingsBulkUpdate($hash, "state", $newState);
            readingsBulkUpdateIfChanged($hash, "lastConnection", keys( %values )." values captured in ".$values{durationFetchReadings}." s",1);
            Nina_Log $hash, 4, keys( %values )." values captured";
        } else {
	    readingsBulkUpdate( $hash, "lastConnection", "no data found" );
            Nina_Log $hash, 1, "No data found. Check global device for latitude/longitude attributes";
        }
    }
    
    readingsEndUpdate( $hash, 1 );
    
    if( AttrVal($name,'intervalAtWarnLevel','') ne '' && ReadingsVal($name,'WarnLevelMax',0) > 1 ) {
        Nina_IntervalAtWarnLevel($hash);
        Nina_Log $hash, 5, "run Sub IntervalAtWarnLevel"; 
    }
}

#####################################
sub Nina_Aborted($) {

    my ($hash) = @_;
    delete( $hash->{helper}{RUNNING_PID} );
}


#####################################
sub Nina_JSONAcquire($$) {

    my ($hash, $URL)  = @_;
    my $name    = $hash->{NAME};
    
    return unless (defined($hash->{NAME}));
 
    Nina_Log $hash, 4, "Start capturing of $URL";

if      (!defined($hash->{helper}{httpref})) { 
          $hash->{helper}{httpref} = {
		url        => "$URL",
		timeout    => 5,
		hash       => $hash,
		method     => "GET",
		header     => "",
		keepalive  => 1,
#		loglevel   => 2,   #just for testing purposes, if not set, loglevel is 4
                sslargs => { SSL_version => 'TLSv12' },  
		};
    Nina_Log $hash, 4, "1. https-request prepared";
}
else {
          $hash->{helper}{httpref}{url} = "$URL";
    Nina_Log $hash, 4, "n. https-request prepared";
}
    my ($err, $data) = HttpUtils_BlockingGet($hash->{helper}{httpref});
     
    if ( $err ne "" ) {
    	my $err_log  =  "Can't get $URL -- " . $err;
        readingsSingleUpdate($hash, "lastConnection", $err, 1);
        Nina_Log $hash, 1, "Error: $err_log";
        return "Error|Error " . $err;
    }
    else {
#      $hash->{helper}{httpref} = "";
    }
    Nina_Log $hash, 5, length($data)." characters captured:  $data";
    return $data;
}
#####################################
# check if geoposition is in polygon or nearer than distance-attribute

sub Nina_IsInArea {
	my ($hash, $lat, $lon, $polygon) = @_;
	my @p = split /\s/,$polygon;
	my $wn = 0;
	my $d = undef;

	sub distance {
		my ($lat1, $lon1, $lat2, $lon2, $unit) = @_;
		if (($lat1 == $lat2) && ($lon1 == $lon2)) {
			return 0;
		} else {
		my $theta = $lon1 - $lon2;
		my $dist = sin(_deg2rad($lat1)) * sin(_deg2rad($lat2)) + cos(_deg2rad($lat1)) * cos(_deg2rad($lat2)) * cos(_deg2rad($theta));
		$dist  = _acos($dist);
		$dist = _rad2deg($dist);
		return $dist * 60 * 1.852;
		# $dist = $dist * 60 * 1.1515;
		# if ($unit eq "K") {
		#   $dist = $dist * 1.609344;
		# } elsif ($unit eq "N") {
		#   $dist = $dist * 0.8684;
		# };
		# 	return ($dist);
		};
	};

	sub isLeft {
		my ($p0x, $p0y, $p1x, $p1y, $p2x, $p2y) = @_;
		return (($p1x - $p0x) * ($p2y - $p0y)
            - ($p2x -  $p0x) * ($p1y - $p0y));
	};

        return(0,0) if (scalar(@p) < 3);

	for (my $i=0; $i < (scalar(@p) - 1); $i++) {
		my ($x1, $y1) = split /,/,$p[$i];
		if ($x1 > 0 && $y1 > 0) {
		my ($x2, $y2) = split /,/,$p[$i +1];

		my $di = distance($lat, $lon, $y1, $x1);
		if (!$d or $di < $d) {
			$d = $di;
			#print "$d $y1 $x1 \n";
		};

		if ($y1 <= $lat) {
#    Nina_Log $hash, 3, "area:   latitude ge: y1=$y1  y2=$y2";
			if ($y2 > $lat) { # an upward crossing
#   Nina_Log $hash, 3, "area:   counter before addition: $wn, x1=$x1 x2=$x2 y1=$y1 y2=$y2 ";
				++$wn if (isLeft($x1, $y1, $x2, $y2, $lon, $lat) > 0);
#    Nina_Log $hash, 3, "area:   counter after addition: $wn, x1=$x1 x2=$x2 y1=$y1 y2=$y2 ";
			};
		} elsif ($y2 <= $lat) { # a downward crossing
#    Nina_Log $hash, 3, "area:   latitude ge: y2=$y2 ; counter before substraction: $wn, x1=$x1 x2=$x2 y1=$y1 y2=$y2  ";
			--$wn if (isLeft($x1, $y1, $x2, $y2, $lon, $lat) < 0);
#    Nina_Log $hash, 3, "area:   counter after substraction: $wn, x1=$x1 x2=$x2 y1=$y1 y2=$y2 ";
		};	
		};	
	};

	return (1, 0) if $wn; # location is in Area
	return (0, $d); # location is _not_ in Area but $d km away

	sub _acos {
		my ($rad) = @_;
		my $ret = atan2(sqrt(1 - $rad**2), $rad);
		return $ret;
	};

	sub _deg2rad {
		my ($deg) = @_;
		my $pi = atan2(1,1) * 4;
		return ($deg * $pi / 180);
	};


	sub _rad2deg {
		my ($rad) = @_;
		my $pi = atan2(1,1) * 4;
		return ($rad * 180 / $pi);
	};

};

#####################################
# prepare warning message for readings update

sub Nina_preparemessage {

    my ($hash,$warning,$i,$ii,$distance) = @_;

    my %severitycolor   = ( "0" => "green", 
                            "1" => "unknown", # <===== FIX HERE
                            "2" => "unknown", # <===== FIX HERE
                            "3" => "unknown", # <===== FIX HERE
                            "4" => "orange",
                            "5" => "unknown", # <===== FIX HERE
                            "6" => "unknown", # <===== FIX HERE
                            "7" => "orange",
                            "8" => "gelb",
                            "9" => "gelb", # <===== FIX HERE
                            "10" => "orange",
                            "11" => "rot",
                            "12" => "violett" );

    my %color   = ( "0 255 0" => "green", 
                    "255 255 0" => "yellow",
                    "255 153 0" => "orange",
                    "255 0 0" => "red",
                    "173 0 99" => "violet" );

        my %warnlevel = ( "green" => "0",
                            "yellow" => "1",
                            "orange" => "2",
                            "red" => "3",
                            "violet" => "4",
                            "Cancel" => "0",
                            "Alert" => "4",
                            "Update" => "4" );
	my $message = Nina_content($hash,"_EventID",$warning->{'identifier'},$i) if (defined($warning->{'identifier'})); 
################## test to eliminate old contents of reading if position has changed ###################
#	       if ($rName =~ m/_EventID/) {
#	          if (ReadingsVal($hash->{NAME}, "Warn_0".$i."_EventID", 0) ne $warning->{'identifier'}) {
#		     $new_warnings_count++;  # new readings counter
#                     Nina_Log $hash, 2, "Delete old warning $i before rewrite";
#  if ($i < 10) {
#my $vartemp = "$hash->{NAME} Warn_0".$i."_.*";
#    Nina_Log $hash, 3, "String before deletereading: $vartemp";
#                $vartemp = CommandDeleteReading(undef, $vartemp);
#    Nina_Log $hash, 3, "return string after deletereading: $vartemp";
#                CommandDeleteReading(undef, "$hash->{NAME} Warn_0${Counter}_.*") if ($Counter < 10);
#                CommandDeleteReading(undef, "$hash->{NAME} Warn_${Counter}_.*") if ($Counter > 9);
#}
#                     CommandDeleteReading(undef, "$hash->{NAME} Warn_0".$i."_.*") # delete all readings of warning
#                  }
#                  readingsBulkUpdateIfChanged( $hash, $rName, $rValue,1 );    # update of reading with event for _EventID, if changed
#		}
################################################################################################################
	$message .= Nina_content($hash,"_Distance",$distance,$i);
	$message .= Nina_content($hash,"_Creation",$warning->{'sent'},$i) if (defined($warning->{'sent'}));
	$message .= Nina_content($hash,"_Sender",$warning->{'sender'},$i) if (defined($warning->{'sender'})); 
	$message .= Nina_content($hash,"_Severity",$warning->{'info'}[0]{'severity'},$i) if (defined($warning->{'info'}[0]{'severity'})); 
	$message .= Nina_content($hash,"_End",$warning->{'info'}[0]{'expires'},$i) if (defined($warning->{'info'}[0]{'expires'})); 
	$message .= Nina_content($hash,"_Geocode",$warning->{'info'}[0]{'area'}[$ii]{'geocode'}[0]{'valueName'},$i) if (defined($warning->{'info'}[0]{'area'}[$ii]{'geocode'}[0]{'value'})); 

	Nina_Log $hash, 2, "Warn_".$i."_status: ".$warning->{'status'} if (defined($warning->{'status'}) && $warning->{'status'} ne "Actual"); 
	Nina_Log $hash, 2, "Warn_".$i."_scope: ".$warning->{'scope'} if (defined($warning->{'scope'}) && $warning->{'scope'} ne "Public"); 
	Nina_Log $hash, 2, "Warn_".$i."_msgType: ".$warning->{'msgType'} if (defined($warning->{'msgType'}) && $warning->{'msgType'} ne "Alert" && $warning->{'msgType'} ne "Cancel"&& $warning->{'msgType'} ne "Update"); 
	Nina_Log $hash, 2, "Warn_".$i."_certainty: ".$warning->{'info'}[0]{'certainty'} if (defined($warning->{'info'}[0]{'certainty'}) && $warning->{'info'}[0]{'certainty'} ne "Observed" && $warning->{'info'}[0]{'certainty'} ne "Unknown"); 
	Nina_Log $hash, 2, "Warn_".$i."_urgency: ".$warning->{'info'}[0]{'urgency'} if (defined($warning->{'info'}[0]{'urgency'}) && $warning->{'info'}[0]{'urgency'} ne "Immediate" && $warning->{'info'}[0]{'urgency'} ne "Unknown"); 
# severity bei dwd scheinbar korrespondierend zur Farbe orange=Moderate, rot=Severe, violett=Extreme, Nina: Minor
	Nina_Log $hash, 2, "Warn_".$i."_severity: ".$warning->{'info'}[0]{'severity'} if (defined($warning->{'info'}[0]{'severity'}) && $warning->{'info'}[0]{'severity'} ne "Severe" && $warning->{'info'}[0]{'severity'} ne "Moderate" && $warning->{'info'}[0]{'severity'} ne "Extreme" && $warning->{'info'}[0]{'severity'} ne "Minor"); 
	Nina_Log $hash, 2, "Warn_".$i."_responseType: ".$warning->{'info'}[0]{'responseType'}[0] if (defined($warning->{'info'}[0]{'responseType'}[0]) && $warning->{'info'}[0]{'responseType'}[0] ne "Prepare" && $warning->{'info'}[0]{'responseType'}[0] ne "Monitor"&& $warning->{'info'}[0]{'responseType'}[0] ne "None"); 

#        Nina_Log $hash, 4, "Warn_".$i."_levelName: ".$warning->{'payload'}{'levelName'};
#        $message .= "Warn_".$i."_levelName|".$warning->{'payload'}{'levelName'}."|";

	my $uclang = "EN";
	if (AttrVal( $hash->{NAME}, 'lang',undef) ) {
		$uclang = uc AttrVal( $hash->{NAME}, 'lang','');
	} else {
		# Begin Language by AttrVal
		if ( $hash->{CountryCode} ~~ [ 'DE' ] ) {
			$uclang = "DE";
		} else {
			$uclang = "EN";
		}
	}

#   values of Category: Safety, Fire, Other, Met, Infra
	$message .= Nina_content($hash,"_Category",$warning->{'info'}[0]{'category'}[0],$i) if (defined($warning->{'info'}[0]{'category'}[0]));
	$message .= Nina_content($hash,"_Contact",$warning->{'info'}[0]{'contact'},$i) if (defined($warning->{'info'}[0]{'contact'})); 
	$message .= Nina_content($hash,"_Area",$warning->{'info'}[0]{'area'}[$ii]{'areaDesc'},$i) if (defined($warning->{'info'}[0]{'area'}[$ii]{'areaDesc'})); 
	$message .= Nina_content($hash,"_Instruction",$warning->{'info'}[0]{'instruction'},$i) if (defined($warning->{'info'}[0]{'instruction'})); 
	$message .= Nina_content($hash,"_LongText",$warning->{'info'}[0]{'description'},$i) if (defined($warning->{'info'}[0]{'description'})); 
	$message .= Nina_content($hash,"_Web",$warning->{'info'}[0]{'web'},$i) if (defined($warning->{'info'}[0]{'web'}));

	my $event, my $shorttext = "";
	$event = $warning->{'info'}[0]{'event'} if (defined($warning->{'info'}[0]{'event'})); 
	$shorttext = $warning->{'info'}[0]{'headline'} if (defined($warning->{'info'}[0]{'headline'}));
	$message .= Nina_content($hash,"_ShortText",$shorttext,$i) if (defined($shorttext));
        $message .= Nina_content($hash,"_MsgType",$warning->{'msgType'},$i) if (defined($warning->{'msgType'}));

	if (defined($warning->{'sender'}) && substr($warning->{'sender'},4,3) ne "dwd" && substr($warning->{'sender'},4,4) ne "hoch") {
	   $message .= Nina_content($hash,"_Sendername",$warning->{'info'}[0]{'parameter'}[0]{'value'},$i) if (defined($warning->{'info'}[0]{'parameter'}[0]{'value'})); 
#	   $message .= Nina_content($hash,"_Level",$warnlevel{$warning->{'msgType'}},$i) if (defined($warning->{'msgType'}));
	} 
	else {
	   $message .= Nina_content($hash,"_Sendername",$warning->{'info'}[0]{'senderName'},$i); 
	   $message .= Nina_content($hash,"_Event",$warning->{'info'}[0]{'event'},$i) if (defined($warning->{'info'}[0]{'event'})); 
#	Nina_Log $hash, 2, "Warning with sender ".$warning->{'sender'}." error line 797 event: ".$warning->{'info'}[0]{'event'}." eventCode: ".$warning->{'info'}[0]{'eventCode'}; 
            if (defined($warning->{'info'}[0]{'eventCode'})) {
            for my $Counter (0 .. scalar(@{$warning->{'info'}[0]{'eventCode'}})-1) {
	 	if($warning->{'info'}[0]{'eventCode'}[$Counter]{'valueName'} eq "AREA_COLOR") {
		   my $color_text = $color{$warning->{'info'}[0]{'eventCode'}[$Counter]{'value'}};
		   $message .= Nina_content($hash,"_Color",$color_text,$i);
#		   $message .= Nina_content($hash,"_Level",$warnlevel{$color_text},$i);
	    	}
	 	elsif($warning->{'info'}[0]{'eventCode'}[$Counter]{'valueName'} eq "GROUP") {
		   $event .= ", ".$warning->{'info'}[0]{'eventCode'}[$Counter]{'value'};
	    	}
	    }
	    }
	} 
	
	$message .= Nina_content($hash,"_Event",$event,$i) if (defined($event));

	return $message;
					
};

#####################################
# asyncronous callback by blocking
sub Nina_content($$$$) {

	my ($hash,$field,$value,$i) = @_;
	my $string;
        
	if ($i < 10) {
	   $string = "Warn_0".$i.$field."|".$value."|";
	}
	else {
	   $string = "Warn_".$i.$field."|".$value."|";
	}
        Nina_Log $hash, 4, $string;
	return $string;
	
}

########################################
sub Nina_deletewarning($$) {

    my ( $hash, $readingspec ) = @_;

    my $message="";

    foreach my $reading (grep { /$readingspec/ }
                                keys %{$hash->{READINGS}} ) {
       readingsDelete($hash, $reading);
       $message .= "$reading \n"
    }

    $message = "deleted readings: $message" if($message);

    return $message;
}

########################################
sub Nina_Log($$$) {

    my ( $hash, $loglevel, $text ) = @_;
    my $xline       = ( caller(0) )[2];

    my $xsubroutine = ( caller(1) )[3];
    my $sub         = ( split( ':', $xsubroutine ) )[2];
    $sub =~ s/Nina_//;

    my $instName = ( ref($hash) eq "HASH" ) ? $hash->{NAME} : $hash;
    Log3 $instName, $loglevel, "$MODUL $instName: $sub.$xline " . $text;
}

# /assets/images/icons/ic_unwetter_weiss.png  /assets/images/icons/ic_hochwasser_weiss.png /assets/images/icons/notfalltipps.png /assets/images/icons/kontakt.png /assets/images/icons/notfalltipps-w.png /assets/images/icons/ic_mowa.png /assets/images/icons/dwd_logo.png
#                $ret .= '<tr><td class="NinaIcon" style="vertical-align:top;"><img src="http://www.unwetterzentrale.de/images/icons/gewitter-gelb.gif"></td>';
#               $ret .= '<tr><td class="NinaIcon" style="vertical-align:top;"><img src="'.'https://warnung.bund.de/assets/images/icons/ic_hochwasser_weiss.png'.'"></td>';


#####################################
sub NinaAsHtml($;$) {

    my ( $name, $items ) = @_;
    my $ret  = '';
    my $hash = $defs{$name};

    my $htmlsequence   = AttrVal( $name, "htmlsequence",   "none" );
    my $htmltitle      = AttrVal( $name, "htmltitle",      "" );
    my $htmltitleclass = AttrVal( $name, "htmltitleclass", "" );

    my $attr;
    if ( AttrVal( $name, "htmlattr", "none" ) ne "none" ) {
        $attr = AttrVal( $name, "htmlattr", "" );
    }
    else {
        $attr = 'width="100%"';
    }

    if ( ReadingsVal( $name, "WarnCount", 0 ) != 0 ) {

        $ret .= '<table><tr><td>';
        $ret .=
            '<table class="block" '
          . $attr
          . '><tr><th class="'
          . $htmltitleclass
          . '" colspan="2">'
          . $htmltitle
          . '</th></tr>';

        if ( $htmlsequence eq "descending" ) {
            for (
                my $i = ReadingsVal( $name, "WarnCount", -1 ) - 1 ;
                $i >= 0 ;
                $i--
              )
            {
                $ret .= NinaHtmlFrame($hash,"Warn_" . $i,$attr,1) if($i > 9);
                $ret .= NinaHtmlFrame($hash,"Warn_0" . $i,$attr,1) if($i < 10);

			}
        }
        else {
###
            for ( my $i = 0 ; $i < ReadingsVal( $name, "WarnCount", 0 ) ; $i++ )
            {

                $ret .= NinaHtmlFrame($hash,"Warn_" . $i,$attr,1) if($i > 9);
                $ret .= NinaHtmlFrame($hash,"Warn_0" . $i,$attr,1) if($i < 10);
            }
        }
###

        $ret .= '</table>';
        $ret .= '</td></tr>';
        $ret .= '</table>';

    }
    else {

        $ret .= '<table><tr><td>';
        $ret .=
            '<table class="block wide" width="600px"><tr><th class="'
          . $htmltitleclass
          . '" colspan="2">'
          . $htmltitle
          . '</th></tr>';
        $ret .= '<tr><td class="NinaIcon" style="vertical-align:top;">';

        # language by AttrVal
        if ( $hash->{CountryCode} ~~ [ 'DE', 'AT', 'CH' ] ) {
            $ret .= '<b>Keine Warnungen</b>';
        }
        elsif ( $hash->{CountryCode} ~~ ['NL'] ) {
            $ret .= '<b>Geen waarschuwingen</b>';
        }
        elsif ( $hash->{CountryCode} ~~ ['FR'] ) {
            $ret .= '<b>Aucune alerte</b>';
        }
        else {
            $ret .= '<b>No Warnings</b>';
        }

        # end language by AttrVal
        $ret .= '</td></tr>';
        $ret .= '</table>';
        $ret .= '</td></tr>';
        $ret .= '</table>';
    }

    return $ret;
}

#####################################
sub NinaAsHtmlLite($;$) {

    my ( $name, $items ) = @_;
    my $ret            = '';
    my $hash           = $defs{$name};
    my $htmlsequence   = AttrVal( $name, "htmlsequence", "none" );
    my $htmltitle      = AttrVal( $name, "htmltitle", "" );
    my $htmltitleclass = AttrVal( $name, "htmltitleclass", "" );
    my $attr;

    if ( AttrVal( $name, "htmlattr", "none" ) ne "none" ) {
        $attr = AttrVal( $name, "htmlattr", "" );
    }
    else {
        $attr = 'width="100%"';
    }

    if ( ReadingsVal( $name, "WarnCount", "" ) != 0 ) {

        $ret .= '<table><tr><td>';
        $ret .=
            '<table class="block" '
          . $attr
          . '><tr><th class="'
          . $htmltitleclass
          . '" colspan="2">'
          . $htmltitle
          . '</th></tr>';

        if ( $htmlsequence eq "descending" ) {
            for (
                my $i = ReadingsVal( $name, "WarnCount", "" ) - 1 ;
                $i >= 0 ;
                $i--
              )
            {
                $ret .= NinaHtmlFrame($hash,"Warn_" . $i,$attr,0) if($i > 9);
                $ret .= NinaHtmlFrame($hash,"Warn_0" . $i,$attr,0) if($i < 10);
            }
        }
        else {
            for ( my $i = 0 ;
                $i < ReadingsVal( $name, "WarnCount", "" ) ; $i++ )
            {
                $ret .= NinaHtmlFrame($hash,"Warn_" . $i,$attr,0) if($i > 9);
                $ret .= NinaHtmlFrame($hash,"Warn_0" . $i,$attr,0) if($i < 10);
            }
        }
        $ret .= '</table>';
        $ret .= '</td></tr>';
        $ret .= '</table>';

    }
    else {

        $ret .= '<table><tr><td>';
        $ret .=
            '<table class="block wide" width="600px"><tr><th class="'
          . $htmltitleclass
          . '" colspan="2">'
          . $htmltitle
          . '</th></tr>';
        $ret .= '<tr><td class="NinaIcon" style="vertical-align:top;">';

        # language by AttrVal
        if ( $hash->{CountryCode} ~~ [ 'DE', 'AT', 'CH' ] ) {
            $ret .= '<b>Keine Warnungen</b>';
        }
        elsif ( $hash->{CountryCode} ~~ ['NL'] ) {
            $ret .= '<b>Geen waarschuwingen</b>';
        }
        elsif ( $hash->{CountryCode} ~~ ['FR'] ) {
            $ret .= '<b>Aucune alerte</b>';
        }
        else {
            $ret .= '<b>No Warnings</b>';
        }

        # end language by AttrVal
        $ret .= '</td></tr>';
        $ret .= '</table>';
        $ret .= '</td></tr>';
        $ret .= '</table>';
    }

    return $ret;
}

#####################################
sub NinaHtmlFrame($$$$) {

    my %severitycolor   = ( "Minor" => "yellow", 
                            "Moderate" => "orange",
                            "Severe" => "red",
                            "Extreme" => "fuchsia" );
my %icon_tab = ( "CAP\@hochwasserzentralen.de" => "https://warnung.bund.de/assets/images/icons/ic_hochwasser_weiss.png", 
                 "CAP\@dwd.de" => "https://warnung.bund.de/assets/images/icons/ic_unwetter_weiss.png" );

		my ($hash,$readingStart,$attr,$parm) = @_;

		my $ret = "";
		my $name = $hash->{NAME};
 my $icon = $icon_tab{ReadingsVal( $name, $readingStart . "_Sender", "")};
 $icon = "https://warnung.bund.de/assets/images/icons/ic_mowa_weiss.png" if(!defined($icon));
 my $iconcolor = "";
  $iconcolor = $severitycolor{ReadingsVal( $name, $readingStart . "_Severity", "")} if(ReadingsVal( $name, $readingStart . "_MsgType", "") ne "Cancel");

		$ret .=
'<tr><td class="NinaIcon" style="vertical-align:top;padding: 15px; background-color: '
		. $iconcolor
		. ';height : 50px"><img src="'
#		  . ReadingsVal( $name, $readingStart . "_IconURL", "" )
               . $icon
		  . '"></td>';
		$ret .=
			'<td class="NinaValue"><b>'
		  . ReadingsVal( $name, $readingStart . "_ShortText", "" )
		  . '</b><br><br>';
		$ret .= ReadingsVal( $name, $readingStart . "_LongText", "" )
		  . '<br><br>' if($parm);

		$ret .= NinaHtmlTimestamp($hash,$readingStart . "_Creation",$attr);
		$ret .= NinaHtmlTimestamp($hash,$readingStart . "_End",$attr);
		$ret .= '</tr></table>';
		$ret .= '</td></tr>';

		return $ret;

}

#####################################
sub NinaHtmlTimestamp($$$) {

my @DEText = qw(Anfang: Ende: Uhr);
my @NLText = qw(Begin: Einde: uur);
my @FRText = ("Valide Ã  partir du:", "Jusqu\'au:", "heure");
my @ENText = qw(Start: End: hour);

my ($hash,$reading,$attr) = @_;

				 my $ret, my $StartEnd = "";
				 my $name = $hash->{NAME};
				 
				if (substr($reading,8,1) eq "C") {
				$StartEnd = 0;
				$ret .=
                        '<table '
                      . $attr
					  . '><tr><th></th><th></th></tr><tr>';
			}
			else {
				$StartEnd = 1;
			}


                # language by AttrVal
                if ( $hash->{CountryCode} ~~ [ 'DE', 'AT', 'CH' ] ) {
                    $ret .=
                        "<td><b>$DEText[$StartEnd]</b></td><td>";
                }
                elsif ( $hash->{CountryCode} ~~ ['NL'] ) {
                    $ret .=
                        "<td><b>$NLText[$StartEnd]</b></td><td>";
                }
                elsif ( $hash->{CountryCode} ~~ ['FR'] ) {
                    $ret .=
                        "<td><b>$FRText[$StartEnd]</b></td><td>";
                }
                else {
                    $ret .=
                        "<td><b>$ENText[$StartEnd]</b></td><td>";
                }
                $ret .= ReadingsVal( $name, $reading, "" ) 
                      . "</td>";		      
				return $ret;

}



#####################################
sub Nina_IntervalAtWarnLevel($) {

    my $hash        = shift;
    
    my $name        = $hash->{NAME};
    my $warnLevel   = ReadingsVal($name,'WarnLevelMax',0);
    my @valuestring = split( ',', AttrVal($name,'intervalAtWarnLevel','') );
    my %warnLevelInterval;
    
    
    readingsSingleUpdate($hash,'currentIntervalMode','warn',0);
    
    foreach( @valuestring ) {
        my @values = split( '=' , $_ );
        $warnLevelInterval{$values[0]} = $values[1];
    }
    
    if( defined($warnLevelInterval{$warnLevel}) and $hash->{INTERVALWARN} != $warnLevelInterval{$warnLevel} ) {
        $hash->{INTERVALWARN} = $warnLevelInterval{$warnLevel};
        RemoveInternalTimer( $hash );
        InternalTimer(gettimeofday() + $hash->{INTERVALWARN}, "Nina_Start", $hash, 1 );
        Nina_Log $hash, 4, "restart internal timer with interval $hash->{INTERVALWARN}";
    } else {
        RemoveInternalTimer( $hash );
        InternalTimer(gettimeofday() + $hash->{INTERVALWARN}, "Nina_Start", $hash, 1 );
        Nina_Log $hash, 4, "restart internal timer with interval $hash->{INTERVALWARN}";
    }
}




##################################### 
1;





=pod

=item device
=item summary       extracts desaster and weather warnings like the official german warning app Nina
=item summary_DE    extrahiert Katastrophen- u. Wetterwarnung vergleichbar der offiziellen Warn-App Nina

=begin html

<a name="Nina"></a>
<h3>Nina</h3>
<ul>
   <a name="Ninadefine"></a>
   This modul extracts desaster and weather warnings like <a href="https://warnung.bund.de/meldungen">warnung.bund.de/meldungen</a>.
   <br/>
   Therefore the same interface is used as the official german warn app Nina does.
   A maximum of 30 warnings will be served.
   The module filters the official warnings checking if the location is within the defined area of a warning. If attr distance is used, warnings with
   distance between nearest border of warning area and location lower than distance are selected too.
   Additionally the module provides a few functions to create HTML-Templates which can be used with weblink.<br><br>
   Technical hint:
   Most readings are only updated if changed, except "state". Don't expect events, if the reading isn't changed.<br>
   Events are in general NOT generated for Warn_xy_* readings, except Warn_xy_EventID.
   <br><br>
   <i>The following Perl-Modules are used within this module: JSON, Encode::Guess </i>.
   <br/><br/>
   <b>Define</b>
   <ul>
      <br>
      <code>define &lt;Name&gt; Nina [CountryCode] [INTERVAL]</code>
      <br><br>
      Example:
      <br>
      <code>
        define Nina_device Nina DE 90<br>
        attr Nina_device distance 25<br>
        attr Nina_device latitude 50.000001<br>
        attr Nina_device longitude 9.99999<br><br>
        define warningweblink weblink htmlCode {NinaAsHtml("Nina_device")}<br>
        define warningweblinkLite weblink htmlCode {NinaAsHtmlLite("Nina_device")}
      </code>
      <br>&nbsp;

      <li><code>[CountryCode]</code>
         <br>
         Defines language for html-views. Possible values: DE|EN|FR|NL<br/>
      </li><br>
      <li><code>[INTERVAL]</code>
         <br>
         Defines the refresh interval. The interval is defined in seconds, so an interval of 3600 means that every hour a refresh will be triggered onetimes. 
         <br>
      </li><br>
      <br>
      <br>&nbsp;
   </ul>
   <br>

   <a name="Ninaget"></a>
   <b>Get</b>
   <ul>
      <br>
      <li><code>no get functions supported
      </li><br>
   </ul>  
  
   <br>

   <a name="Ninaset"></a>
   <b>Set</b>
   <ul>
      <br>
      <li><code>set &lt;name&gt; update</code>
         <br>
         Executes an immediate update of warnings.
      </li><br>
   </ul>  
  
   <br>
   <a name="Ninaattr"></a>
   <b>Attributes</b>
   <ul>
      <br>
      </li>
      <li><code>distance</code>
         <br>
         selects additional warnings of warning areas with distance lower than distance between location and nearest border of warning area. 
         <br>
      </li>
      </li>
      <li><code>latitude</code>
         <br>
         geographical latitude[decimal degrees] of the location(latitude of global device will be used if omitted)
         <br>
      </li>
      <li><code>longitude</code>
         <br>
         geographical longitude[decimal degrees] of the location(longitude of global device will be used if omitted)
         <br>
      </li>
      <li><code>disableDWD</code>
         <br>
         0|1 if defined DWD warnings will be omitted(source DWD).  
         <br>
      </li>
      <li><code>disableLHP</code>
         <br>
         0|1 if defined flood warnings will be omitted(source LänderHochwasserPortale).  
         <br>
      </li>
      <li><code>sort_readings_by</code>
         <br>
         distance|severity|creationde - defines how warnings will be sorted (distance=ascending,severity=descending,creation=descending)).  
         <br>
      </li>
      <li><code>htmlsequence</code>
         <br>
         define warn order of html output. ascending(default) means sorted as device-sorting; descending means reversed display 
         <br>
      </li>
      <li><code>htmlattr</code>
         <br>
         influences general html-layout; e.g. width="50%" to get smaller html-output
         <br>
      </li>
      <li><code>htmltitle</code>
         <br>
          title / header for the html ouput
          <br>
       </li>
       <li><code>htmltitleclass</code>
          <br>
          css-Class of title / header for the html ouput
          <br>
       </li>
      <li><code>intervalAtWarnLevel</code>
         <br>
         define the interval per warnLevel. Example: 2=1800,3=900,4=300
         <br>
      </li>
      <br>
   </ul>  

   <br>

   <a name="Ninareading"></a>
   <b>Readings</b>
   <ul>
      <br>
      <li><b>Warn_</b><i>00|01|02|03...|29</i><b>_...</b> - active warnings</li>
      <li><b>NewWarnings</b> - last execution created NewWarnings warnings </li>
      <li><b>WarnCount</b> - overall warnings count</li>
      <li><b>WarnCountinArea</b> - just local(distance=0) warnings are counted</li>
      <li><b>WarnMaxLevel</b> - max. warn level(severity) of selected warnings</li>
      <li><b>Warn_</b><i>x</i><b>_Area</b> - location of warning(government area) </li>
      <li><b>Warn_</b><i>x</i><b>_Category</b> - category of warning</li>
      <li><b>Warn_</b><i>x</i><b>_Color</b> - color of warning(only dwd); meaning of colors like DWD uses</li>
      <li><b>Warn_</b><i>x</i><b>_Contact</b> - institution to be contacted to get further informations</li>
      <li><b>Warn_</b><i>x</i><b>_Creation</b> - creation timestamp of warning</li>
      <li><b>Warn_</b><i>x</i><b>_Distance</b> - shortest distance of location to warning area</li>
      <li><b>Warn_</b><i>x</i><b>_End</b> - warning end timestamp</li>
      <li><b>Warn_</b><i>x</i><b>_Event</b> - ??? </li>
      <li><b>Warn_</b><i>x</i><b>_EventID</b> - warning EventID </li>
      <li><b>Warn_</b><i>x</i><b>_Geocode</b> - Text depending on geocode of warning</li>
      <li><b>Warn_</b><i>x</i><b>_Instruction</b> - warning instruction given by authorities</li>
      <li><b>Warn_</b><i>x</i><b>_LongText</b> - detailed warn text</li>
      <li><b>Warn_</b><i>x</i><b>_MsgType</b> - Alert/Cancel</li>
      <li><b>Warn_</b><i>x</i><b>_Sender</b> - responsible institution(code) sending warning</li>
      <li><b>Warn_</b><i>x</i><b>_Sendername</b> - responsible institution(name) sending warning</li>
      <li><b>Warn_</b><i>x</i><b>_Severity</b> - Severity of warning </li>
      <ul>
        <li>Unknown</li>
        <li>Minor</li>
        <li>Moderate</li>
        <li>Severe</li>
        <li>Extreme</li>
      </ul>
      <li><b>Warn_</b><i>x</i><b>_ShortText</b> - short warn text</li>
      <li><b>currentIntervalMode</b> - default/warn, Interval is read from INTERVAL or INTERVALWARN Internal</li>
      <li><b>lastConnection</b> - No. of characters read </li>
      <li><b>durationFetchReadings</b> - ???? </li>
   </ul>
   <br>

   <a name="Ninaweblinks"></a>
   <b>Weblinks</b>
   <ul>
      <br>

      With the additional implemented functions <code>NinaAsHtml, NinaAsHtmlLite</code> HTML-Code will be created to display warnings, using weblinks.
      <br><br><br>
      Example:
      <br>
      <li><code>define warningweblink weblink htmlCode {NinaAsHtml("Nina_device")}</code></li>
      <br>
      <li><code>define warningweblinkLite weblink htmlCode {NinaAsHtmlLite("Nina_device")}</code></li>
      <br>
      <br/><br/>
   </ul>
   <br>
 

</ul> 



=end html

=begin html_DE

<a name="Nina"></a>
<h3>Nina</h3> 
<ul>
   <a name="Ninadefine"></a>
   Das Modul extrahiert Bevölkerungsschutzwarnungen(Nina) von ....
   <br/>
   HierfÃ¼r wird die selbe Schnittstelle verwendet die auch die Nina-App nutzt.
   Es werden maximal 30 Warnungen zur VerfÃ¼gung gestellt.
   Weiterhin verfÃ¼gt das Modul Ã¼ber HTML-Templates welche als weblink verwendet werden kÃ¶nnen.
   <br>
   <i>Es nutzt die Perl-Module JSON, Encode::Guess und HTML::Parse</i>.
   <br/><br/>
   <b>Define</b>
   <ul>
      <br>
      <code>define &lt;Name&gt; Nina [L&auml;ndercode] [INTERVAL]</code>
      <br><br><br>
      Beispiel:
      <br>
      <code>define Nina_device Nina DE 90</code>
      <br>&nbsp;

      <li><code>[L&auml;ndercode]</code>
         <br>
                  Definiert Sprache für html-views. Possible values: DE|EN|FR|NL<br/>
      </li><br>
      <li><code>[INTERVAL]</code>
         <br>
         Definiert das Interval zur aktualisierung der Warnungen. Das Interval wird in Sekunden angegeben, somit aktualisiert das Modul bei einem Interval von 3600 jede Stunde 1 mal. 
         <br>
      </li><br>
   </ul>
   <br>

   <a name="Ninaget"></a>
   <b>Get</b>
   <ul>
      <br>
      <li><code>get nicht implementiert</code>
         <br>
      </li><br>
   </ul>  
  
   <br>

     <a name="Ninaset"></a>
   <b>Set</b>
   <ul>
      <br>
      <li><code>set &lt;name&gt; update</code>
         <br>
         Startet sofort ein neues Auslesen der Warnungen.
      </li><br>
   </ul>  
  
   <br>

   <a name="Ninaattr"></a>
   <b>Attribute</b>
   <ul>
      <br>
      </li>
      <li><code>distance</code>
         <br>
	selektiert zusätzliche Warnungen, die über die Lokation hinausgehen anhand der kürzesten Entfernung zum Polygon einer Warnung.         
         <br>
      </li>
      </li>
      <li><code>latitude</code>
         <br>
         geographische Breite[Dezimalgrad] der Lokation(latitude des global device wird genutzt, sofern das Attribut nicht angegeben wird)
         <br>
      </li>
      <li><code>longitude</code>
         <br>
         geographische Länge[Dezimalgrad] der Lokation(latitude des global device wird genutzt, sofern das Attribut nicht angegeben wird)
         <br>
      </li>
      <li><code>disableDWD</code>
         <br>
         0|1 wenn definiert, werden keine DWD Warnungen selektiert(source DWD).  
         <br>
      </li>
      <li><code>disableLHP</code>
         <br>
         0|1 wenn definiert, werden keine Hochwasser-Warnungen selektiert(source LänderHochwasserPortale).  
         <br>
      </li>
      <li><code>sort_readings_by</code>
         <br>
         distance|severity|creation - definiert die Sortierreihenfolge der Warnmeldungen. (distance=ascending,severity=descending,creation=descending).  
         <br>
      </li>
      <li><code>htmlattr</code>
         <br>
         beeinflusst das allgemeine html-layout; z.B. width="50%" um eine geringere Bildschirmbreite zu erhalten
         <br>
      </li>
      <li><code>htmlsequence</code>
         <br>
         Anzeigereihenfolge der html warnungen. ascending(default)=wie im device; descending=umgekehrt zum device. 
         <br>
      </li>
      <li><code>htmltitle</code>
         <br>
         Titel / Ueberschrift der HTML Ausgabe 
         <br>
      </li>
      <li><code>htmltitleclass</code>
         <br>
         css-Class des Titels der HTML Ausgabe 
         <br>
      </li>
      <li><code>intervalAtWarnLevel</code>
         <br>
         konfiguriert das Interval je nach WarnLevel. Beispiel: 2=1800,3=900,4=300
         <br>
      </li>

      <br>
   </ul>  

   <br>

   <a name="Ninareading"></a>
   <b>Readings</b>
   <ul>
      <br>
      <li><b>Warn_</b><i>00|01...|29</i><b>_...</b> - aktive Warnmeldungen</li>
      <li><b>WarnCount</b> - Anzahl der aktiven Warnmeldungen</li>
      <li><b>WarnCountInArea</b> - Anzahl der aktiven Warnmeldungen mit location innerhalb des Warngebiets</li>
      <li><b>WarnLevelMax</b> - Gesamt Warn Level (abhängig von severity)</li>
      <li><b>Warn_</b><i>x</i><b>_Area</b> - Region(Stadt, Gemeinde, Landkreis, Bundesland) </li>
      <li><b>Warn_</b><i>x</i><b>_Category</b> - ??? </li>
      <li><b>Warn_</b><i>x</i><b>_Creation</b> - Warnungs Erzeugung </li>
      <li><b>Warn_</b><i>x</i><b>_Distance</b> - Entfernung in km zur Warnregion</li>
      <li><b>Warn_</b><i>x</i><b>_End</b> - Warn Ende</li>
      <li><b>Warn_</b><i>x</i><b>_Event</b> - ??? </li>
      <li><b>Warn_</b><i>x</i><b>_EventID</b> - EventID der Warnung </li>
      <li><b>Warn_</b><i>x</i><b>_Geocode</b> - Text zum geocode der Warnung</li>
      <li><b>Warn_</b><i>x</i><b>_Instruction</b> - Anweisung für die Bevölkerung</li>
      <li><b>Warn_</b><i>x</i><b>_LongText</b> - Langtext der Warnung</li>
      <li><b>Warn_</b><i>x</i><b>_MsgType</b> - Alert/Cancel</li>
      <li><b>Warn_</b><i>x</i><b>_Sender</b> - Kürzel für Absender der Warnung</li>
      <li><b>Warn_</b><i>x</i><b>_Sendername</b> - Name des Absenders der Warnung</li>
      <li><b>Warn_</b><i>x</i><b>_Severity</b> - Schweregrad der Warnung</li>
      <ul>
        <li>Unknown</li>
        <li>Minor</li>
        <li>Moderate</li>
        <li>Severe</li>
        <li>Extreme</li>
      </ul>
      <li><b>Warn_</b><i>x</i><b>_ShortText</b> - Kurzbeschreibung der Warnung</li>
      <li><b>currentIntervalMode</b> - default/warn, aktuell Verwendeter Interval. Internal INTERVAL oder INTERVALWARN</li>
      <li><b>lastConnection</b> - Anz. gelesener character aller Warnquellen </li>
      <li><b>durationFetchReadings</b> - ???? </li>
   </ul>
   <br>

   <a name="Ninaweblinks"></a>
   <b>Weblinks</b>
   <ul>
      <br>

      &Uuml;ber die Funktionen <code>NinaAsHtml, NinaAsHtmlLite</code> wird HTML-Code zur Warnanzeige Ã¼ber weblinks erzeugt.
      <br><br><br>
      Beispiele:
      <br>
      <li><code>define warningweblink weblink htmlCode {NinaAsHtml("Nina_device")}</code></li>
      <br>
      <li><code>define warningweblinkLite weblink htmlCode {NinaAsHtmlLite("Nina_device")}</code></li>
      <br>
      <br/><br/>
   </ul>
   <br>
 

</ul>

=end html_DE
=cut
