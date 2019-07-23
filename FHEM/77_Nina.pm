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
#  $Id: 77_Nina.pm 17646 2018-10-30 11:20:16Z Kölnsolar $
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

my $MODUL           = "Nina";
my $version         = "0.1.0";

# Declare functions
sub Nina_Log($$$);
#sub Nina_Map2Movie($$);
#sub Nina_Map2Image($$);
#sub Nina_Initialize($);
#sub Nina_Define($$);
#sub Nina_Undef($$);
#sub Nina_Set($@);
#sub Nina_Get($@);
#sub Nina_GetCurrent($@);
#sub Nina_GetCurrentHail($);
#sub Nina_JSONAcquire($$);
#sub Nina_Start($);
#sub Nina_Aborted($);
#sub Nina_Done($);
#sub Nina_Run($);
#sub NinaAsHtml($;$);
#sub NinaAsHtmlLite($;$);
#sub NinaAsHtmlFP($;$);
#sub NinaAsHtmlMovie($$);
#sub NinaAsHtmlKarteLand($$);
#sub Nina_GetSeverityColor($$);
#sub Nina_GetNinaLevel($$);
#sub NinaSearchLatLon($$);
#sub NinaSearchAreaID($$);
#sub Nina_IntervalAtWarnLevel($);




#my $countrycode = "DE";
#my $geocode = "05315";
#my $Nina_alert_url = "http://feed.alertspro.meteogroup.com/AlertsPro/AlertsProPollService.php?method=getWarning&language=de&areaID=UWZ" . $countrycode . $geocode;

sub Nina_Initialize($) {

    my ($hash) = @_;
    $hash->{DefFn}    = "Nina_Define";
    $hash->{UndefFn}  = "Nina_Undef";
    $hash->{SetFn}    = "Nina_Set";
    $hash->{GetFn}    = "Nina_Get";
    $hash->{AttrList} = "disableDWD:0,1 ".
			"distance:selectnumbers,0,1,99,0,lin ".
			"download:0,1 ".
                        "savepath ".
                        "maps ".
#                        "humanreadable:0,1 ".
                        "htmlattr ".
                        "htmltitle ".
                        "htmltitleclass ".
                        "htmlsequence:ascending,descending ".
                        "lang ".
                        "latitude ".
                        "longitude ".
                        "sort_readings_by:distance,creation,warnlevel ".
                        "localiconbase ".
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

sub Nina_Get($@) {

    my ( $hash, @a ) = @_;
    my $name    = $hash->{NAME};
   
    if ( $hash->{CountryCode} ~~ [ 'DE' ] ) {
        my $usage   = "Unknown argument $a[1], choose one of Sturm:noArg Schneefall:noArg Regen:noArg Extremfrost:noArg Waldbrand:noArg Gewitter:noArg Glaette:noArg Hitze:noArg Glatteisregen:noArg Bodenfrost:noArg Hagel:noArg ";
     
        return $usage if ( @a < 2 );
       
        if    ($a[1] =~ /^Sturm/)            { Nina_GetCurrent($hash,2); }
#        elsif ($a[1] =~ /^Schneefall/)       { Nina_GetCurrent($hash,3); }
#        elsif ($a[1] =~ /^Regen/)            { Nina_GetCurrent($hash,4); }
#        elsif ($a[1] =~ /^Extremfrost/)      { Nina_GetCurrent($hash,5); }
#        elsif ($a[1] =~ /^Waldbrand/)        { Nina_GetCurrent($hash,6); }
#        elsif ($a[1] =~ /^Gewitter/)         { Nina_GetCurrent($hash,7); }
#        elsif ($a[1] =~ /^Glaette/)          { Nina_GetCurrent($hash,8); }
#        elsif ($a[1] =~ /^Hitze/)            { Nina_GetCurrent($hash,9); }
#        elsif ($a[1] =~ /^Glatteisregen/)    { Nina_GetCurrent($hash,10); }
#        elsif ($a[1] =~ /^Bodenfrost/)       { Nina_GetCurrent($hash,11); }
#        elsif ($a[1] =~ /^Hagel/)            { Nina_GetCurrentHail($hash); }
        else                                 { return $usage; }
    } else {
        my $usage   = "Unknown argument $a[1], choose one of storm:noArg snow:noArg rain:noArg extremfrost:noArg forest-fire:noArg thunderstorms:noArg glaze:noArg heat:noArg glazed-rain:noArg soil-frost:noArg hail:noArg ";
        
        return $usage if ( @a < 2 );
    
        if    ($a[1] =~ /^storm/)            { Nina_GetCurrent($hash,2); }
#        elsif ($a[1] =~ /^snow/)             { Nina_GetCurrent($hash,3); }
#        elsif ($a[1] =~ /^rain/)             { Nina_GetCurrent($hash,4); }
#        elsif ($a[1] =~ /^extremfrost/)      { Nina_GetCurrent($hash,5); }
#        elsif ($a[1] =~ /^forest-fire/)      { Nina_GetCurrent($hash,6); }
#        elsif ($a[1] =~ /^thunderstorms/)    { Nina_GetCurrent($hash,7); }
#        elsif ($a[1] =~ /^glaze/)            { Nina_GetCurrent($hash,8); }
#        elsif ($a[1] =~ /^heat/)             { Nina_GetCurrent($hash,9); }
#        elsif ($a[1] =~ /^glazed-rain/)      { Nina_GetCurrent($hash,10); }
#        elsif ($a[1] =~ /^soil-frost/)       { Nina_GetCurrent($hash,11); }
#        elsif ($a[1] =~ /^hail/)             { Nina_GetCurrentHail($hash); }
        else                                 { return $usage; }

    }
}

###################################
#####################################
sub Nina_GetCurrent($@) {

    my ( $hash, @a ) = @_;
    my $name         = $hash->{NAME};
    my $out;
    my $curTimestamp = time();
    if ( ReadingsVal($name,"WarnCount", 0) eq 0 ) {
        $out = "inactive";
    } else {  
        for(my $i= 0;$i < ReadingsVal($name,"WarnCount", 0);$i++) {
            if (  (ReadingsVal($name,"Warn_".$i."_Start","") le $curTimestamp) &&  (ReadingsVal($name,"Warn_".$i."_End","") ge $curTimestamp) && (ReadingsVal($name,"Warn_".$i."_Type","") eq $a[0])  ) {
                $out= "active"; 
                last;
            } else {
                $out = "inactive";
            }
        }
    }
    
    return $out;
}

#####################################
sub Nina_GetCurrentHail($) {

    my ( $hash ) = @_;
    my $name         = $hash->{NAME};
    my $out;
    my $curTimestamp = time();
    
    if ( ReadingsVal($name,"WarnCount", 0) eq 0 ) {
        $out = "inactive";
    } else {
        for(my $i= 0;$i < ReadingsVal($name,"WarnCount", 0);$i++) {
            if (  (ReadingsVal($name,"Warn_".$i."_Start","") le $curTimestamp) &&  (ReadingsVal($name,"Warn_".$i."_End","") ge $curTimestamp) && (ReadingsVal($name,"Warn_".$i."_Hail","") eq 1)  ) {
                $out= "active"; 
                last;
            } else {
                $out= "inactive";
            }
        }
    }

    return $out;
}

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
    if (AttrVal($hash->{NAME}, "lang", undef) ) {  
        $URL_language=AttrVal($hash->{NAME}, "lang", "");
    } else {
        if ( $hash->{CountryCode} ~~ [ 'DE' ] ) {
            $URL_language="de";
        }
    }
#    $hash->{URL} =  "http://feed.alertspro.meteogroup.com/AlertsPro/AlertsProPollService.php?method=getWarning&language=" . $URL_language . "&areaID=UWZ" . $hash->{CountryCode} . $hash->{PLZ};
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
    my $Nina_download;
    my $Nina_savepath;
    my $Nina_humanreadable;
    my $message;
    my $i=0;    # counter for filtered messages
    
    return unless ( defined($name) );
   
    my $hash = $defs{$name};
    return unless (defined($hash->{NAME}));
    
    my $readingStartTime = time();
    my $attrdownload     = AttrVal( $name, 'download','');
    my $attrsavepath     = AttrVal( $name, 'savepath','');
    my $maps2fetch       = AttrVal( $name, 'maps','');
    
    ## begin redundant Reading switch
    my $attrhumanreadable = AttrVal( $name, 'humanreadable','');
    ## end redundant Reading switch
    
    # preset download
    if ($attrdownload eq "") {  
        $Nina_download = 0;
    } else {
        $Nina_download = $attrdownload;
    }
    
    # preset savepath
    if ($attrsavepath eq "") {
        $Nina_savepath = "/tmp/";
    } else {
        $Nina_savepath = $attrsavepath;
    }
    
    # preset humanreadable
    if ($attrhumanreadable eq "") {
        $Nina_humanreadable = 0;
    } else {
      $Nina_humanreadable = $attrhumanreadable;
    }

    if ( $Nina_download == 1 ) {
        if ( ! defined($maps2fetch) ) { $maps2fetch = "deutschland"; }
            Nina_Log $hash, 4, "Maps2Fetch : ".$maps2fetch;
            my @maps = split(' ', $maps2fetch);
            my $Nina_de_url = "http://www.unwetterzentrale.de/images/map/";
            foreach my $smap (@maps) {
                Nina_Log $hash, 4, "Download map : ".$smap;
                my $img = Nina_Map2Image($hash,$smap);
                if (!defined($img) ) { $img=$Nina_de_url.'deutschland_index.png'; }
                my $code = getstore($img, $Nina_savepath.$smap.".png");        
                if($code == 200) {
                    Nina_Log $hash, 4, "Successfully downloaded map ".$smap;
                } else {
                    Nina_Log $hash, 3, "Failed to download map (".$img.")";
            	}
       	} 
    }

    my ($Nina_warnings, @Nina_records, $enc) = "";

    # acquire the json-response
    my $response = Nina_JSONAcquire($hash,$hash->{URL}); 					     # MoWaS-Meldungen
#    my $response = Nina_JSONAcquire($hash,"http://feed.alertspro.meteogroup.com/AlertsPro/AlertsProPollService.php?method=getWarning&language=de&areaID=UWZDE39517"); 
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
    $Nina_warnings = JSON->new->ascii->decode($response);  #'"' expected, at character offset 2 (before "(end of string)") 
   foreach my $element (@{$Nina_warnings}) {
        push @Nina_records, $element;
    }
    }
    else {
	$message .= $response;
    }
    } 
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
    return "$name|$message" if (defined($message));
     $Nina_warnings = \@Nina_records;
#     @Nina_records;

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
			Nina_Log $hash, 4, "       Record with geocode: ".$single_warning->{'info'}[0]{'area'}[$ii]{'geocode'}[0]{'value'};
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
					$single_warning->{'distance'} = $dist if(!defined($single_warning->{'distance'}) || defined($single_warning->{'distance'}) && $dist < $single_warning->{'distance'}); # || $single_warning->{'distance'} == 0);
					$single_warning->{'area'} = $ii;
				   }
				}
				$iii++;
			}
	Nina_Log $hash, 3, "Severity MoWaS: $single_warning->{'info'}[0]{'severity'} for $single_warning->{'info'}[0]{'area'}[$ii]{'areaDesc'}" if (defined($single_warning->{'info'}[0]{'severity'}) && $single_warning->{'info'}[0]{'severity'} ne "Minor" && defined($single_warning->{'sender'}) && substr($single_warning->{'sender'},4,3) ne "dwd"); 
			$ii++;
		}
		if ($flag_warning_in_area || defined($single_warning->{'distance'})) {
		  $single_warning->{'sent'} = $single_warning->{'info'}[0]{'onset'} if (defined($single_warning->{'info'}[0]{'onset'}));
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
    } elsif ( $sortby eq "warnlevel" ) {
        Nina_Log $hash, 4, "Sorting by warnlevel";
        @sorted =  sort { $b->{warnlevel} <=> $a->{warnlevel} } @Nina_filtered_records;
    } else {
        Nina_Log $hash, 4, "Sorting by distance";
        @sorted =  sort { $a->{distance} <=> $b->{distance} } @Nina_filtered_records;
    }

$i = 0;
    foreach my $single_warning (@sorted) {
       $message .= Nina_preparemessage($hash,$single_warning,$i,$single_warning->{'area'},$single_warning->{'distance'}) ;
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
   
    # all term are separated by "|" , the first is the name of the instance
    my ( $name, %values ) = split( "\\|", $string );
    my $hash = $defs{$name};
    return unless ( defined($hash->{NAME}) );
 
    my $max_level = 0;  
    
    # UnWetterdaten speichern
    readingsBeginUpdate($hash);
    Nina_Log $hash, 5, "Starting Readings Update.";

    if ( defined $values{Error} ) {
        readingsBulkUpdateIfChanged( $hash, "lastConnection", $values{Error} );
    } else {
	my $new_warnings_count  = 0;  # new reading NewWarnings
        while (my ($rName, $rValue) = each(%values) ) {
	    if ($rName ne "WarnCount" && $rName ne "WarnCountInArea") {
	       if ($rName =~ m/_EventID/) {
	          if (ReadingsVal($name, $rName, 0) ne $rValue) {
		     $new_warnings_count++;  # new readings counter
 #                    Nina_Log $hash, 4, "Delete old warning before rewrite"; 
 #                    CommandDeleteReading(undef, "$hash->{NAME} Warn_". substr($rName,5,2)."_.*") # delete all readings of warning
                  }
                  readingsBulkUpdateIfChanged( $hash, $rName, $rValue,1 );    # update of reading with event for _EventID, if changed
		}
	       else {
	           if ($rName =~ m/_Level/) {
		     $max_level = $rValue if ($rValue gt $max_level );  # max level of warnings
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
                CommandDeleteReading(undef, "$hash->{NAME} Warn_0${Counter}_.*") if ($Counter < 10);
                CommandDeleteReading(undef, "$hash->{NAME} Warn_${Counter}_.*") if ($Counter > 9);
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
            readingsBulkUpdateIfChanged($hash, "NewWarnings", $new_warnings_count,1);
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

    my $param = {
		url        => "$URL",
		timeout    => 5,
		hash       => $hash,
		method     => "GET",
		header     => "",  
		};

    my ($err, $data) = HttpUtils_BlockingGet($param);
     
    if ( $err ne "" ) {
    	my $err_log  =  "Can't get $URL -- " . $err;
        readingsSingleUpdate($hash, "lastConnection", $err, 1);
        Nina_Log $hash, 1, "Error: $err_log";
        return "Error|Error " . $err;
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
		my $dist = sin(deg2rad($lat1)) * sin(deg2rad($lat2)) + cos(deg2rad($lat1)) * cos(deg2rad($lat2)) * cos(deg2rad($theta));
		$dist  = acos($dist);
		$dist = rad2deg($dist);
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

	sub acos {
		my ($rad) = @_;
		my $ret = atan2(sqrt(1 - $rad**2), $rad);
		return $ret;
	};

	sub deg2rad {
		my ($deg) = @_;
		my $pi = atan2(1,1) * 4;
		return ($deg * $pi / 180);
	};


	sub rad2deg {
		my ($rad) = @_;
		my $pi = atan2(1,1) * 4;
		return ($rad * 180 / $pi);
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

	$message .= Nina_content($hash,"_Distance",$distance,$i);
	$message .= Nina_content($hash,"_Creation",$warning->{'sent'},$i) if (defined($warning->{'sent'}));
	$message .= Nina_content($hash,"_Sender",$warning->{'sender'},$i) if (defined($warning->{'sender'})); 
	$message .= Nina_content($hash,"_Severity",$warning->{'info'}[0]{'severity'},$i) if (defined($warning->{'info'}[0]{'severity'})); 
	$message .= Nina_content($hash,"_End",$warning->{'info'}[0]{'expires'},$i) if (defined($warning->{'info'}[0]{'expires'})); 
	$message .= Nina_content($hash,"_Geocode",$warning->{'info'}[0]{'area'}[$ii]{'geocode'}[0]{'value'},$i) if (defined($warning->{'info'}[0]{'area'}[$ii]{'geocode'}[0]{'value'})); 

	Nina_Log $hash, 2, "Warn_".$i."_status: ".$warning->{'status'} if (defined($warning->{'status'}) && $warning->{'status'} ne "Actual"); 
	Nina_Log $hash, 2, "Warn_".$i."_scope: ".$warning->{'scope'} if (defined($warning->{'scope'}) && $warning->{'scope'} ne "Public"); 
	Nina_Log $hash, 2, "Warn_".$i."_msgType: ".$warning->{'msgType'} if (defined($warning->{'msgType'}) && $warning->{'msgType'} ne "Alert" && $warning->{'msgType'} ne "Cancel"&& $warning->{'msgType'} ne "Update"); 
	Nina_Log $hash, 2, "Warn_".$i."_certainty: ".$warning->{'info'}[0]{'certainty'} if (defined($warning->{'info'}[0]{'certainty'}) && $warning->{'info'}[0]{'certainty'} ne "Observed" && $warning->{'info'}[0]{'certainty'} ne "Unknown"); 
	Nina_Log $hash, 2, "Warn_".$i."_urgency: ".$warning->{'info'}[0]{'urgency'} if (defined($warning->{'info'}[0]{'urgency'}) && $warning->{'info'}[0]{'urgency'} ne "Immediate" && $warning->{'info'}[0]{'urgency'} ne "Unknown"); 
# severity bei dwd scheinbar korrespondierend zur Farbe orange=Moderate, rot=Severe, violett=Extreme, Nina: Minor
	Nina_Log $hash, 2, "Warn_".$i."_severity: ".$warning->{'info'}[0]{'severity'} if (defined($warning->{'info'}[0]{'severity'}) && $warning->{'info'}[0]{'severity'} ne "Severe" && $warning->{'info'}[0]{'severity'} ne "Moderate" && $warning->{'info'}[0]{'severity'} ne "Extreme" && $warning->{'info'}[0]{'severity'} ne "Minor"); 
	Nina_Log $hash, 2, "Warn_".$i."_responseType: ".$warning->{'info'}[0]{'responseType'} if (defined($warning->{'info'}[0]{'responseType'}) && $warning->{'info'}[0]{'responseType[0]'} ne "Prepare"); 

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
	$message .= Nina_content($hash,"_ShortText",$warning->{'info'}[0]{'headline'},$i) if (defined($warning->{'info'}[0]{'headline'})); 
	$message .= Nina_content($hash,"_LongText",$warning->{'info'}[0]{'description'},$i) if (defined($warning->{'info'}[0]{'description'})); 

	my $event = $warning->{'info'}[0]{'event'} if (defined($warning->{'info'}[0]{'event'})); 

	if (defined($warning->{'sender'}) && substr($warning->{'sender'},4,3) ne "dwd") {
	   $message .= Nina_content($hash,"_Sendername",$warning->{'info'}[0]{'parameter'}[0]{'value'},$i) if (defined($warning->{'info'}[0]{'parameter'}[0]{'value'})); 
	   $message .= Nina_content($hash,"_Level",$warnlevel{$warning->{'msgType'}},$i) if (defined($warning->{'msgType'}));
	} 
	else {
	   $message .= Nina_content($hash,"_Sendername",$warning->{'info'}[0]{'senderName'},$i); 
	   $message .= Nina_content($hash,"_Event",$warning->{'info'}[0]{'event'},$i) if (defined($warning->{'info'}[0]{'event'})); 
            for my $Counter (0 .. scalar(@{$warning->{'info'}[0]{'eventCode'}})-1) {
	 	if($warning->{'info'}[0]{'eventCode'}[$Counter]{'valueName'} eq "AREA_COLOR") {
		   my $color_text = $color{$warning->{'info'}[0]{'eventCode'}[$Counter]{'value'}};
		   $message .= Nina_content($hash,"_Color",$color_text,$i);
		   $message .= Nina_content($hash,"_Level",$warnlevel{$color_text},$i);
	    	}
	 	elsif($warning->{'info'}[0]{'eventCode'}[$Counter]{'valueName'} eq "GROUP") {
		   $event .= ", ".$warning->{'info'}[0]{'eventCode'}[$Counter]{'value'};
	    	}
	    }
	} 
	
	$message .= Nina_content($hash,"_Event",$event,$i); 

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
sub Nina_Log($$$) {

    my ( $hash, $loglevel, $text ) = @_;
    my $xline       = ( caller(0) )[2];

    my $xsubroutine = ( caller(1) )[3];
    my $sub         = ( split( ':', $xsubroutine ) )[2];
    $sub =~ s/Nina_//;

    my $instName = ( ref($hash) eq "HASH" ) ? $hash->{NAME} : $hash;
    Log3 $instName, $loglevel, "$MODUL $instName: $sub.$xline " . $text;
}

########################################
sub Nina_Map2Movie($$) {
    my $Nina_movie_url = "http://www.meteocentrale.ch/uploads/media/";
    my ( $hash, $smap ) = @_;
    my $lmap;

    $smap=lc($smap);

    ## Euro
    $lmap->{'niederschlag-wolken'}=$Nina_movie_url.'Nina_EUROPE_COMPLETE_niwofi.mp4';
    $lmap->{'stroemung'}=$Nina_movie_url.'Nina_EUROPE_COMPLETE_stfi.mp4';
    $lmap->{'temperatur'}=$Nina_movie_url.'Nina_EUROPE_COMPLETE_theta_E.mp4';

    ## DE
    $lmap->{'niederschlag-wolken-de'}=$Nina_movie_url.'Nina_EUROPE_GERMANY_COMPLETE_niwofi.mp4';
    $lmap->{'stroemung-de'}=$Nina_movie_url.'Nina_EUROPE_GERMANY_COMPLETE_stfi.mp4';

    return $lmap->{$smap};
}

########################################
sub Nina_Map2Image($$) {

    my $Nina_de_url = "http://www.unwetterzentrale.de/images/map/";

    my ( $hash, $smap ) = @_;
    my $lmap;
    
    $smap=lc($smap);

    ## Euro
    $lmap->{'europa'}=$Nina_de_url.'europe_index.png';

    ## DE
    $lmap->{'deutschland'}=$Nina_de_url.'deutschland_index.png';
    $lmap->{'deutschland-small'}=$Nina_de_url.'deutschland_preview.png';
    $lmap->{'niedersachsen'}=$Nina_de_url.'niedersachsen_index.png';
    $lmap->{'bremen'}=$Nina_de_url.'niedersachsen_index.png';
    $lmap->{'bayern'}=$Nina_de_url.'bayern_index.png';
    $lmap->{'schleswig-holstein'}=$Nina_de_url.'schleswig_index.png';
    $lmap->{'hamburg'}=$Nina_de_url.'schleswig_index.png';
    $lmap->{'mecklenburg-vorpommern'}=$Nina_de_url.'meckpom_index.png';
    $lmap->{'sachsen'}=$Nina_de_url.'sachsen_index.png';
    $lmap->{'sachsen-anhalt'}=$Nina_de_url.'sachsenanhalt_index.png';
    $lmap->{'nordrhein-westfalen'}=$Nina_de_url.'nrw_index.png';
    $lmap->{'thueringen'}=$Nina_de_url.'thueringen_index.png';
    $lmap->{'rheinland-pfalz'}=$Nina_de_url.'rlp_index.png';
    $lmap->{'saarland'}=$Nina_de_url.'rlp_index.png';
    $lmap->{'baden-wuerttemberg'}=$Nina_de_url.'badenwuerttemberg_index.png';
    $lmap->{'hessen'}=$Nina_de_url.'hessen_index.png';
    $lmap->{'brandenburg'}=$Nina_de_url.'brandenburg_index.png';
    $lmap->{'berlin'}=$Nina_de_url.'brandenburg_index.png';

    ## Isobaren
    $lmap->{'isobaren1'}="http://www.unwetterzentrale.de/images/icons/Nina_ISO_00.jpg";
    $lmap->{'isobaren2'}="http://www.wetteralarm.at/uploads/pics/Nina_EURO_ISO_GER_00.jpg";
    $lmap->{'isobaren3'}="http://www.severe-weather-centre.co.uk/uploads/pics/Nina_EURO_ISO_ENG_00.jpg";

    return $lmap->{$smap};
}

#####################################
sub NinaAsHtml($;$) {

    my ($name,$items) = @_;
    my $ret = '';
    my $hash = $defs{$name};    

    my $htmlsequence = AttrVal($name, "htmlsequence", "none");
    my $htmltitle = AttrVal($name, "htmltitle", "");
    my $htmltitleclass = AttrVal($name, "htmltitleclass", "");


    my $attr;
    if (AttrVal($name, "htmlattr", "none") ne "none") {
        $attr = AttrVal($name, "htmlattr", "");
    } else {
        $attr = 'width="100%"';
    }


    if (ReadingsVal($name, "WarnCount", 0) != 0 ) {
        $ret .= '<table><tr><td>';
        $ret .= '<table class="block" '.$attr.'><tr><th class="'.$htmltitleclass.'" colspan="2">'.$htmltitle.'</th></tr>';
        if ($htmlsequence eq "descending") {
            for ( my $i=ReadingsVal($name, "WarnCount", -1)-1; $i>=0; $i--){
                $ret .= '<tr><td class="NinaIcon" style="vertical-align:top;"><img src="'.ReadingsVal($name, "Warn_0".$i."_IconURL", "").'"></td>';
                $ret .= '<td class="NinaValue"><b>'.ReadingsVal($name, "Warn_0".$i."_ShortText", "").'</b><br><br>';
                $ret .= ReadingsVal($name, "Warn_0".$i."_LongText", "").'<br><br>';
                my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(ReadingsVal($name, "Warn_0".$i."_Start", ""));
                if (length($hour) == 1) {$hour = "0$hour";}
                if (length($min) == 1) {$min = "0$min";}
                # language by AttrVal
                                if ( $hash->{CountryCode} ~~ [ 'DE' ] ) {
                        $ret .= '<table '.$attr.'><tr><th></th><th></th></tr><tr><td><b>Anfang:</b></td><td>'."$DEweekdays[$wday], $mday $DEmonths[$mon] ".(1900+$year)." $hour:$min ".'Uhr</td>';
                                } else {
                                $ret .= '<table '.$attr.'><tr><th></th><th></th></tr><tr><td><b>Start:</b></td><td>'."$ENweekdays[$wday], $mday $ENmonths[$mon] ".(1900+$year)." $hour:$min ".'hour</td>';
                }
                # end language by AttrVal
                ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = undef;
                ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(ReadingsVal($name, "Warn_0".$i."_End", ""));
                if (length($hour) == 1) {$hour = "0$hour";}
                if (length($min) == 1) {$min = "0$min";}
                # language by AttrVal
                if ( $hash->{CountryCode} ~~ [ 'DE' ] ) {
                    $ret .= '<td><b>Ende:</b></td><td>'."$DEweekdays[$wday], $mday $DEmonths[$mon] ".(1900+$year)." $hour:$min ".'Uhr</td>';
                } else {
                    $ret .= '<td><b>End:</b></td><td>'."$ENweekdays[$wday], $mday $ENmonths[$mon] ".(1900+$year)." $hour:$min ".'hour</td>';
                }
                # end language by AttrVal
                $ret .= '</tr></table>';
                $ret .= '</td></tr>';
            }
        } else {
###        
            for ( my $i=0; $i<ReadingsVal($name, "WarnCount", 0); $i++){
                $ret .= '<tr><td class="NinaIcon" style="vertical-align:top;"><img src="'.ReadingsVal($name, "Warn_0".$i."_IconURL", "").'"></td>';
                $ret .= '<td class="NinaValue"><b>'.ReadingsVal($name, "Warn_0".$i."_ShortText", "").'</b><br><br>';
                $ret .= ReadingsVal($name, "Warn_0".$i."_LongText", "").'<br><br>';
                my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(ReadingsVal($name, "Warn_0".$i."_Start", ""));
                if (length($hour) == 1) {$hour = "0$hour";}
                if (length($min) == 1) {$min = "0$min";}
                # language by AttrVal
                if ( $hash->{CountryCode} ~~ [ 'DE' ] ) {
                   $ret .= '<table '.$attr.'><tr><th></th><th></th></tr><tr><td><b>Anfang:</b></td><td>'."$DEweekdays[$wday], $mday $DEmonths[$mon] ".(1900+$year)." $hour:$min ".'Uhr</td>';
                } else {
                   $ret .= '<table '.$attr.'><tr><th></th><th></th></tr><tr><td><b>Start:</b></td><td>'."$ENweekdays[$wday], $mday $ENmonths[$mon] ".(1900+$year)." $hour:$min ".'hour</td>';
                }
                # end language by AttrVal
                ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = undef;
                ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(ReadingsVal($name, "Warn_0".$i."_End", ""));
                if (length($hour) == 1) {$hour = "0$hour";}
                if (length($min) == 1) {$min = "0$min";}
                # language by AttrVal
                if ( $hash->{CountryCode} ~~ [ 'DE' ] ) {
                    $ret .= '<td><b>Ende:</b></td><td>'."$DEweekdays[$wday], $mday $DEmonths[$mon] ".(1900+$year)." $hour:$min ".'Uhr</td>';
                } else {
                    $ret .= '<td><b>End:</b></td><td>'."$ENweekdays[$wday], $mday $ENmonths[$mon] ".(1900+$year)." $hour:$min ".'hour</td>';
                }
                # end language by AttrVal
                $ret .= '</tr></table>';
                $ret .= '</td></tr>';
            }
        }
###
        $ret .= '</table>';
        $ret .= '</td></tr>';
        $ret .= '</table>';
    } else {
        $ret .= '<table><tr><td>';
        $ret .= '<table class="block wide" width="600px"><tr><th class="'.$htmltitleclass.'" colspan="2">'.$htmltitle.'</th></tr>';
        $ret .= '<tr><td class="NinaIcon" style="vertical-align:top;">';
        # language by AttrVal
        if ( $hash->{CountryCode} ~~ [ 'DE' ] ) {
            $ret .='<b>Keine Warnungen</b>';
        } else {
            $ret .='<b>No Warnings</b>';
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

    my ($name,$items) = @_;
    my $ret = '';
    my $hash = $defs{$name}; 
    my $htmlsequence = AttrVal($name, "htmlsequence", "none");
    my $htmltitle = AttrVal($name, "htmltitle", "");
    my $htmltitleclass = AttrVal($name, "htmltitleclass", "");
    my $attr;
    
    if (AttrVal($name, "htmlattr", "none") ne "none") {
        $attr = AttrVal($name, "htmlattr", "");
    } else {
        $attr = 'width="100%"';
    }
    
    if (ReadingsVal($name, "WarnCount", "") != 0 ) {

        $ret .= '<table><tr><td>';
        $ret .= '<table class="block" '.$attr.'><tr><th class="'.$htmltitleclass.'" colspan="2">'.$htmltitle.'</th></tr>';
        if ($htmlsequence eq "descending") {
            for ( my $i=ReadingsVal($name, "WarnCount", "")-1; $i>=0; $i--){
# /assets/images/icons/ic_unwetter_weiss.png  /assets/images/icons/ic_hochwasser_weiss.png /assets/images/icons/notfalltipps.png /assets/images/icons/kontakt.png /assets/images/icons/notfalltipps-w.png /assets/images/icons/ic_mowa.png /assets/images/icons/dwd_logo.png
#                $ret .= '<tr><td class="NinaIcon" style="vertical-align:top;"><img src="http://warnung.bund.de/bbk.webapp/assets/images/Schutzzeichen_share.png"></td>';
                $ret .= '<tr><td class="NinaIcon" style="vertical-align:top;"><img src="'.ReadingsVal($name, "Warn_0".$i."_IconURL", "").'"></td>';
                $ret .= '<td class="NinaValue"><b>'.ReadingsVal($name, "Warn_0".$i."_ShortText", "").'</b><br><br>';
                my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(ReadingsVal($name, "Warn_0".$i."_Start", ""));
                if (length($hour) == 1) {$hour = "0$hour";}
                if (length($min) == 1) {$min = "0$min";}
                # language by AttrVal
                if ( $hash->{CountryCode} ~~ [ 'DE' ] ) {
                   $ret .= '<table '.$attr.'><tr><th></th><th></th></tr><tr><td><b>Anfang:</b></td><td>'."$DEweekdays[$wday], $mday $DEmonths[$mon] ".(1900+$year)." $hour:$min ".'Uhr</td>';
                } else {
                   $ret .= '<table '.$attr.'><tr><th></th><th></th></tr><tr><td><b>Start:</b></td><td>'."$ENweekdays[$wday], $mday $ENmonths[$mon] ".(1900+$year)." $hour:$min ".'hour</td>';
                }
# end language by AttrVal
                ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = undef;
                ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(ReadingsVal($name, "Warn_0".$i."_End", ""));
                if (length($hour) == 1) {$hour = "0$hour";}
                if (length($min) == 1) {$min = "0$min";}
                # language by AttrVal
                if ( $hash->{CountryCode} ~~ [ 'DE' ] ) {
                    $ret .= '<td><b>Ende:</b></td><td>'."$DEweekdays[$wday], $mday $DEmonths[$mon] ".(1900+$year)." $hour:$min ".'Uhr</td>';
                } else {
                    $ret .= '<td><b>End:</b></td><td>'."$ENweekdays[$wday], $mday $ENmonths[$mon] ".(1900+$year)." $hour:$min ".'hour</td>';
                }
                # end language by AttrVal
                $ret .= '</tr></table>';
                $ret .= '</td></tr>';
            }
        } else {
            for ( my $i=0; $i<ReadingsVal($name, "WarnCount", ""); $i++){
                $ret .= '<tr><td class="NinaIcon" style="vertical-align:top;"><img src="'.ReadingsVal($name, "Warn_0".$i."_IconURL", "").'"></td>';
                $ret .= '<td class="NinaValue"><b>'.ReadingsVal($name, "Warn_0".$i."_ShortText", "").'</b><br><br>';
                my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(ReadingsVal($name, "Warn_0".$i."_Start", ""));
                if (length($hour) == 1) {$hour = "0$hour";}
                if (length($min) == 1) {$min = "0$min";}
                # language by AttrVal
                if ( $hash->{CountryCode} ~~ [ 'DE' ] ) {
                   $ret .= '<table '.$attr.'><tr><th></th><th></th></tr><tr><td><b>Anfang:</b></td><td>'."$DEweekdays[$wday], $mday $DEmonths[$mon] ".(1900+$year)." $hour:$min ".'Uhr</td>';
                } else {
                   $ret .= '<table '.$attr.'><tr><th></th><th></th></tr><tr><td><b>Start:</b></td><td>'."$ENweekdays[$wday], $mday $ENmonths[$mon] ".(1900+$year)." $hour:$min ".'hour</td>';
                }
                # end language by AttrVal
                ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = undef;
                ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(ReadingsVal($name, "Warn_0".$i."_End", ""));
                if (length($hour) == 1) {$hour = "0$hour";}
                if (length($min) == 1) {$min = "0$min";}
                # language by AttrVal
                if ( $hash->{CountryCode} ~~ [ 'DE' ] ) {
                    $ret .= '<td><b>Ende:</b></td><td>'."$DEweekdays[$wday], $mday $DEmonths[$mon] ".(1900+$year)." $hour:$min ".'Uhr</td>';
                } else {
                    $ret .= '<td><b>End:</b></td><td>'."$ENweekdays[$wday], $mday $ENmonths[$mon] ".(1900+$year)." $hour:$min ".'hour</td>';
                }
                # end language by AttrVal
                $ret .= '</tr></table>';
                $ret .= '</td></tr>';
            }
        }    
        $ret .= '</table>';
        $ret .= '</td></tr>';
        $ret .= '</table>';
    } else {
        $ret .= '<table><tr><td>';
        $ret .= '<table class="block wide" width="600px"><tr><th class="'.$htmltitleclass.'" colspan="2">'.$htmltitle.'</th></tr>';
        $ret .= '<tr><td class="NinaIcon" style="vertical-align:top;">';
        # language by AttrVal
        if ( $hash->{CountryCode} ~~ [ 'DE' ] ) {
            $ret .='<b>Keine Warnungen</b>';
        } else {
            $ret .='<b>No Warnings</b>';
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
sub NinaAsHtmlFP($;$) {

    my ($name,$items) = @_;
    my $tablewidth = ReadingsVal($name, "WarnCount", "") * 80;
    my $htmlsequence = AttrVal($name, "htmlsequence", "none");
    my $htmltitle = AttrVal($name, "htmltitle", "");
    my $htmltitleclass = AttrVal($name, "htmltitleclass", "");
    my $ret = '';
    
    $ret .= '<table class="Nina-fp" style="width:'.$tablewidth.'px"><tr><th class="'.$htmltitleclass.'" colspan="'.ReadingsVal($name, "WarnCount", "none").'">'.$htmltitle.'</th></tr>';
    $ret .= "<tr>";
    
    if ($htmlsequence eq "descending") {
        for ( my $i=ReadingsVal($name, "WarnCount", "")-1; $i>=0; $i--){
            $ret .= '<td class="NinaIcon"><img width="80px" src="'.ReadingsVal($name, "Warn_0".$i."_IconURL", "").'"></td>';
        }
    } else {
        for ( my $i=0; $i<ReadingsVal($name, "WarnCount", ""); $i++){
            $ret .= '<td class="NinaIcon"><img width="80px" src="'.ReadingsVal($name, "Warn_0".$i."_IconURL", "").'"></td>';
        }
    } 
    $ret .= "</tr>";
    $ret .= '</table>';

    return $ret;
}

#####################################
sub NinaAsHtmlMovie($$) {

    my ($name,$land) = @_;
    my $url = Nina_Map2Movie($name,$land);
    my $hash = $defs{$name};

    my $ret = '<table><tr><td>';

    $ret .= '<table class="block wide">';
    $ret .= '<tr class="even"><td>';

    if(defined($url)) {
        $ret .= '<video controls="controls">';
        $ret .= '<source src="'.$url.'" type="video/mp4">';
        $ret .= '</video>';
    } else {
        # language by AttrVal
        if ( $hash->{CountryCode} ~~ [ 'DE' ] ) {
            $ret .= 'unbekannte Landbezeichnung';
        } else {
            $ret .='unknown movie setting';
        }
        # end language by AttrVal
    }

    $ret .= '</td></tr></table></td></tr>';
    $ret .= '</table>';

    return $ret;
}

#####################################
sub NinaAsHtmlKarteLand($$) {

    my ($name,$land) = @_;
    my $url = Nina_Map2Image($name,$land);
    my $hash = $defs{$name};

    my $ret = '<table><tr><td>';
    
    $ret .= '<table class="block wide">';
    $ret .= '<tr class="even"><td>';
    
    if(defined($url)) {
        $ret .= '<img src="'.$url.'">';
    } else {
        # language by AttrVal
        if ( $hash->{CountryCode} ~~ [ 'DE' ] ) {
            $ret .= 'unbekannte Landbezeichnung';
        } else {
            $ret .='unknown map setting';
        }       
        # end language by AttrVal
    }
    
    $ret .= '</td></tr></table></td></tr>';
    $ret .= '</table>';
    
    return $ret;
}

#####################################
sub Nina_GetSeverityColor($$) {
    my ($name,$Ninalevel) = @_;
    my $alertcolor       = "";

    my %NinaSeverity = ( "0" => "green",
                            "1" => "orange",
                            "2" => "yellow",
                            "3" => "red",
                            "4" => "violet");

    return $NinaSeverity{$Ninalevel};
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
##
##      Nina Helper Functions
##
#####################################

sub NinaSearchLatLon($$) {

    my ($name,$loc)    = @_;
    my $url      = "http://alertspro.geoservice.meteogroup.de/weatherpro/SearchFeed.php?search=".$loc;

#    my $agent    = LWP::UserAgent->new( env_proxy => 1, keep_alive => 1, protocols_allowed => ['http'], timeout => 10 );
#    my $request  = HTTP::Request->new( GET => $url );
#    my $response = $agent->request($request);
#    my $err_log  = "Can't get $url -- " . $response->status_line unless( $response->is_success );

#    if ( $err_log ne "" ) {
#        print "Error|Error " . $response->status_line;
#    }
    
    use XML::Simple qw(:strict);
    use Data::Dumper;
    use Encode qw(decode encode);

    my $Ninaxmlparser = XML::Simple->new();
    #my $xmlres = $parser->XMLin(
    my $search = ""; #$Ninaxmlparser->XMLin($response->content, KeyAttr => { city => 'id' }, ForceArray => [ 'city' ]);

    my $ret = '<html><table><tr><td>';

    $ret .= '<table class="block wide">';

            $ret .= '<tr class="even">';
            $ret .= "<td><b>city</b></td>";
            $ret .= "<td><b>country</b></td>";
            $ret .= "<td><b>latitude</b></td>";
            $ret .= "<td><b>longitude</b></td>";
            $ret .= '</tr>';

    foreach my $locres ($search->{cities}->{city})
        {
            my $linecount=1;
            while ( my ($key, $value) = each(%$locres) ) {
                if ( $linecount % 2 == 0 ) {
                    $ret .= '<tr class="even">';
                } else {
                    $ret .= '<tr class="odd">';
                }
                $ret .= "<td>".encode('utf-8',$value->{'name'})."</td>";
                $ret .= "<td>$value->{'country-name'}</td>";
                $ret .= "<td>$value->{'latitude'}</td>";
                $ret .= "<td>$value->{'longitude'}</td>";

                my @headerHost = grep /Host/, @FW_httpheader;
                $headerHost[0] =~ s/Host: //g; 
 
                my $aHref="<a href=\"http://".$headerHost[0]."/fhem?cmd=get+".$name."+AreaID+".$value->{'latitude'}.",".$value->{'longitude'}."\">Get AreaID</a>";
                $ret .= "<td>".$aHref."</td>";
                $ret .= '</tr>';
                $linecount++;
            }
        }
        
    $ret .= '</table></td></tr>';
    $ret .= '</table></html>';

    return $ret;

}

#####################################
sub NinaSearchAreaID($$) {
    my ($lat,$lon) = @_;
    my $url = "http://feed.alertspro.meteogroup.com/AlertsPro/AlertsProPollService.php?method=lookupCoord&lat=".$lat."&lon=".$lon;
    
#    my $agent    = LWP::UserAgent->new( env_proxy => 1, keep_alive => 1, protocols_allowed => ['http'], timeout => 10 );
#    my $request   = HTTP::Request->new( GET => $url );
#    my $response = $agent->request($request);
#    my $err_log = "Can't get $url -- " . $response->status_line unless( $response->is_success );

#    if ( $err_log ne "" ) {
#        print "Error|Error " . $response->status_line;
#    }
    use JSON;
    my @perl_scalar = ""; #@{JSON->new->utf8->decode($response->content)};


    my $AreaType = $perl_scalar[0]->{'AREA_TYPE'};
    my $CC       = substr $perl_scalar[0]->{'AREA_ID'}, 3, 2;
    my $AreaID   = substr $perl_scalar[0]->{'AREA_ID'}, 5, 5;   

    if ( $AreaType eq "Nina" ) {
        my $ret = '<html>Please use the following statement to define Unwetterzentrale for your location:<br /><br />';
        $ret   .= '<table width=100%><tr><td>';
        $ret   .= '<table class="block wide">';
        $ret   .= '<tr class="even">';
        $ret   .= "<td height=100><center><b>define Unwetterzentrale Nina $CC $AreaID 3600</b></center></td>";
        $ret   .= '</tr>';
        $ret   .= '</table>';
        $ret   .= '</td></tr></table>';
    
        $ret   .= '<br />';
        $ret   .= 'You can also use weblinks to add weathermaps. For a list of possible Weblinks see Commandref. For example to add the Europe Map use:<br />';
    
        $ret   .= '<table width=100%><tr><td>';
        $ret   .= '<table class="block wide">';
        $ret   .= '<tr class="even">';
        $ret   .= "<td height=100><center>define Nina_Map_Europe weblink htmlCode { NinaAsHtmlKarteLand('Unwetterzentrale','europa') }</center></td>";
        $ret   .= '</tr>';
        $ret   .= '</table>';
        $ret   .= '</td></tr></table>';
    
        $ret   .= '</html>';
     
        return $ret;
    } else {
        return "Sorry, nothing found or not implemented";
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
   Additionally the module provides a few functions to create HTML-Templates which can be used with weblink.(maybe in future versions)<br><br>
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
        attr Nina_device download 1<br>
        attr Nina_device humanreadable 1<br>
        attr Nina_device maps eastofengland unitedkingdom<br><br>
        define UnwetterDetails weblink htmlCode {NinaAsHtml("Nina_device")}<br>
        define UnwetterMapE_UK weblink htmlCode {NinaAsHtmlKarteLand("Nina_device","eastofengland")}<br>
        define UnwetterLite weblink htmlCode {NinaAsHtmlLite("Nina_device")}
        define UnwetterMovie weblink htmlCode {NinaAsHtmlMovie("Nina_device","clouds-precipitation-uk")}
      </code>
      <br>&nbsp;

      <li><code>[CountryCode]</code>
         <br>
         Possible values: DE<br/>
      </li><br>
      <li><code>[INTERVAL]</code>
         <br>
         Defines the refresh interval. The interval is defined in seconds, so an interval of 3600 means that every hour a refresh will be triggered onetimes. 
         <br>
      </li><br>

      <br><br><br>
      <br>

      <br>&nbsp;


   </ul>
   <br>

   <a name="Ninaget"></a>
   <b>Get</b>
   <ul>
      <br>
      <li><code>get &lt;name&gt; soil-frost</code>
         <br>
         give info about current soil frost (active|inactive).
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
      <li><code>sort_readings_by</code>
         <br>
         define how warnings will be sorted (distance|warnlevel|creation).  
         <br>
      </li>
      <li><code>download</code>
         <br>
         Download maps during update (0|1). 
         <br>
      <li><code>savepath</code>
         <br>
         Define where to store the map png files (default: /tmp/). 
         <br>
      </li>
      <li><code>maps</code>
         <br>
         Define the maps to download space seperated. For possible values see <code>NinaAsHtmlKarteLand</code>.
         <br>
      </li>
      <li><code>humanreadable</code>
         <br>
         Add additional Readings Warn_?_Start_Date, Warn_?_Start_Time, Warn_?_End_Date and Warn_?_End_Time containing the coresponding timetamp in a human readable manner. Additionally Warn_?_NinaLevel_Str and Warn_?_Type_Str will be added to device readings (0|1).
         <br>
      </li>
      <li><code>lang</code>
         <br>
         Overwrite requested language for short and long warn text. (de|en). 
         <br>
      </li>
      <li><code>htmlsequence</code>
         <br>
         define warn order of html output (ascending|descending). 
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
      <li><code>localiconbase</code>
         <br>
         define baseurl to host your own thunderstorm warn pics (filetype is png). 
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
      <li><b>Warn_</b><i>00|01|02|03...|09</i><b>_...</b> - active warnings</li>
      <li><b>NewWarnings</b> - last execution created NewWarnings warnings </li>
      <li><b>WarnCount</b> - overall warnings count</li>
      <li><b>WarnCountinArea</b> - just local(distance=0) warnings are counted</li>
      <li><b>WarnNinaLevel</b> - max. warn level of filtere warnings</li>
      <li><b>WarnNinaLevel_Color</b> - total warn level color</li>
      <li><b>WarnNinaLevel_Str</b> - total warn level string</li>
      <li><b>Warn_</b><i>0</i><b>_Area</b> - location of warning(government area) </li>
      <li><b>Warn_</b><i>0</i><b>_Category</b> - category of warning</li>
      <li><b>Warn_</b><i>0</i><b>_Color</b> - color of warning; meaning of colors like DWD uses</li>
      <li><b>Warn_</b><i>0</i><b>_Contact</b> - institution to be contacted to get further informations</li>
      <li><b>Warn_</b><i>0</i><b>_Creation</b> - creation timestamp of warning</li>
      <li><b>Warn_</b><i>0</i><b>_Distance</b> - shortest distance of location to warning area</li>
      <li><b>Warn_</b><i>0</i><b>_EventID</b> - warning EventID </li>
      <li><b>Warn_</b><i>0</i><b>_Geocode</b> - geocode of warning - may be omitted in future releases</li>
      <li><b>Warn_</b><i>0</i><b>_Instruction</b> - warning instruction given by authorities</li>
      <li><b>Warn_</b><i>0</i><b>_LongText</b> - detailed warn text</li>
      <li><b>Warn_</b><i>0</i><b>_ShortText</b> - short warn text</li>
      <li><b>Warn_</b><i>0</i><b>_Sender</b> - responsible institution(code) sending warning</li>
      <li><b>Warn_</b><i>0</i><b>_Sendername</b> - responsible institution(name) sending warning</li>
      <li><b>Warn_</b><i>0</i><b>_Severity</b> - Severity of warning </li>
      <ul>
        <li><b>0</b> - unknown/canceled</li>
        <li><b>1</b> - minor</li>
        <li><b>2</b> - moderate</li>
        <li><b>3</b> - severe</li>
        <li><b>4</b> - extreme</li>
      </ul>
      <li><b>Warn_</b><i>0</i><b>_NinaLevel</b> - Severity of thunderstorm (0-5)</li>
      <li><b>Warn_</b><i>0</i><b>_NinaLevel_Str</b> - Severity of thunderstorm (text)</li>
      <li><b>Warn_</b><i>0</i><b>_levelName</b> - Level Warn Name</li>
      <li><b>Warn_</b><i>0</i><b>_IconURL</b> - cumulated URL to display warn-icons from <a href="http://www.unwetterzentrale.de">www.unwetterzentrale.de</a></li>
      <li><b>Warn_</b><i>0</i><b>_Creation_Date</b> - warning creation datum </li>
      <li><b>Warn_</b><i>0</i><b>_Creation_Time</b> - warning creation time </li>
      <li><b>Warn_</b><i>0</i><b>_Start</b> - begin of warnperiod</li>
      <li><b>Warn_</b><i>0</i><b>_Start_Date</b> - start date of warnperiod</li>
      <li><b>Warn_</b><i>0</i><b>_Start_Time</b> - start time of warnperiod</li>
      <li><b>Warn_</b><i>0</i><b>_End</b> - end of warnperiod</li>
      <li><b>Warn_</b><i>0</i><b>_End_Date</b> - end date of warnperiod</li>
      <li><b>Warn_</b><i>0</i><b>_End_Time</b> - end time of warnperiod</li>
      <li><b>currentIntervalMode</b> - default/warn, Interval is read from INTERVAL or INTERVALWARN Internal</li>
   </ul>
   <br>

   <a name="Ninaweblinks"></a>
   <b>Weblinks</b>
   <ul>
      <br>

      With the additional implemented functions <code>NinaAsHtml, NinaAsHtmlLite, NinaAsHtmlFP, NinaAsHtmlKarteLand and NinaAsHtmlMovie</code> HTML-Code will be created to display warnings and weathermovies, using weblinks.
      <br><br><br>
      Example:
      <br>
      <li><code>define UnwetterDetailiert weblink htmlCode {NinaAsHtml("Nina_device")}</code></li>
      <br>
      <li><code>define UnwetterLite weblink htmlCode {NinaAsHtmlLite("Nina_device")}</code></li>
      <br>
      <li><code>define UnwetterFloorplan weblink htmlCode {NinaAsHtmlFP("Nina_device")}</code></li>
      <br>
      <li><code>define UnwetterKarteLand weblink htmlCode {NinaAsHtmlKarteLand("Nina_device","Bayern")}</code></li>
      <ul>
        <li>The second parameter should be one of:
        <ul>
          <li>europa</li>
          <br/>
          <li>deutschland</li>
          <li>deutschland-small</li>
          <li>niedersachsen</li>
          <li>bremen</li>
          <li>bayern</li>
          <li>schleswig-holstein</li>
          <li>hamburg</li>
          <li>mecklenburg-vorpommern</li>
          <li>sachsen</li>
          <li>sachsen-anhalt</li>
          <li>nordrhein-westfalen</li>
          <li>thueringen</li>
          <li>rheinland-pfalz</li>
          <li>saarland</li>
          <li>baden-wuerttemberg</li>
          <li>hessen</li>
          <li>brandenburg</li>
          <li>berlin</li>
          <br/>
          <li>isobaren1</li>
          <li>isobaren2</li>
          <li>isobaren3</li>
        </ul>          
        </li>
      </ul>
      <li><code>define UnwetterKarteMovie weblink htmlCode {NinaAsHtmlMovie("Nina_device","currents")}</code></li>
      <ul>
        <li>The second parameter should be one of:
        <ul>
          <li>niederschlag-wolken</li>
          <li>stroemung</li>
          <li>temperatur</li>
          <br/>
          <li>niederschlag-wolken-de</li>
          <li>stroemung-de</li>
          <br/>
        </ul>          
        </li>
      </ul>

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
   Das Modul extrahiert Bevölkerungsschutzwarnungen(Nina) von <a href="http://www.unwetterzentrale.de">www.unwetterzentrale.de</a>.
   <br/>
   HierfÃ¼r wird die selbe Schnittstelle verwendet die auch die Android App <a href="http://www.alertspro.com">Alerts Pro</a> nutzt.
   Es werden maximal 10 Standortbezogene Unwetterwarnungen zur VerfÃ¼gung gestellt.
   Weiterhin verfÃ¼gt das Modul Ã¼ber HTML-Templates welche als weblink verwendet werden kÃ¶nnen.
   <br>
   <i>Es nutzt die Perl-Module JSON, Encode::Guess und HTML::Parse</i>.
   <br/><br/>
   <b>Define</b>
   <ul>
      <br>
      <code>define &lt;Name&gt; Nina [L&auml;ndercode] [Postleitzahl] [INTERVAL]</code>
      <br><br><br>
      Beispiel:
      <br>
      <code>define Nina_device Nina DE 86405 3600</code>
      <br>&nbsp;

      <li><code>[L&auml;ndercode]</code>
         <br>
         M&ouml;gliche Werte: DE ...<br/>
      </li><br>
      <li><code>[Postleitzahl/AreaID]</code>
         <br>
         Die Postleitzahl/AreaID des Ortes fÃ¼r den Unwetterinformationen abgefragt werden sollen. 
         <br>
      </li><br>
      <li><code>[INTERVAL]</code>
         <br>
         Definiert das Interval zur aktualisierung der Unwetterwarnungen. Das Interval wird in Sekunden angegeben, somit aktualisiert das Modul bei einem Interval von 3600 jede Stunde 1 mal. 
         <br>
      </li><br>
   </ul>
   <br>

   <a name="Ninaget"></a>
   <b>Get</b>
   <ul>
      <br>
      <li><code>get &lt;name&gt; Bodenfrost</code>
         <br>
         Gibt aus ob aktuell eine Bodenfrostwarnung besteht (active|inactive).
      </li><br>
      <li><code>get &lt;name&gt; Extremfrost</code>
         <br>
         Gibt aus ob aktuell eine Extremfrostwarnung besteht (active|inactive).
      </li><br>
      <li><code>get &lt;name&gt; Gewitter</code>
         <br>
         Gibt aus ob aktuell eine Gewitter Warnung besteht (active|inactive).
      </li><br>
      <li><code>get &lt;name&gt; Glaette</code>
         <br>
         Gibt aus ob aktuell eine Glaettewarnung besteht (active|inactive).
      </li><br>
      <li><code>get &lt;name&gt; Glatteisregen</code>
         <br>
         Gibt aus ob aktuell eine Glatteisregen Warnung besteht (active|inactive).
      </li><br>
      <li><code>get &lt;name&gt; Hagel</code>
         <br>
         Gibt aus ob aktuell eine Hagel Warnung besteht (active|inactive).
      </li><br>
      <li><code>get &lt;name&gt; Hitze</code>
         <br>
         Gibt aus ob aktuell eine Hitze Warnung besteht (active|inactive).
      </li><br>
      <li><code>get &lt;name&gt; Regen</code>
         <br>
         Gibt aus ob aktuell eine Regen Warnung besteht (active|inactive).
      </li><br>
      <li><code>get &lt;name&gt; Schneefall</code>
         <br>
         Gibt aus ob aktuell eine Schneefall Warnung besteht (active|inactive).
      </li><br>
      <li><code>get &lt;name&gt; Sturm</code>
         <br>
         Gibt aus ob aktuell eine Sturm Warnung besteht (active|inactive).
      </li><br>
      <li><code>get &lt;name&gt; Waldbrand</code>
         <br>
         Gibt aus ob aktuell eine Waldbrand Warnung besteht (active|inactive).
      </li><br>


   </ul>  
  
   <br>

     <a name="Ninaset"></a>
   <b>Set</b>
   <ul>
      <br>
      <li><code>set &lt;name&gt; update</code>
         <br>
         Startet sofort ein neues Auslesen der Unwetterinformationen.
      </li><br>
   </ul>  
  
   <br>

   <a name="Ninaattr"></a>
   <b>Attribute</b>
   <ul>
      <br>
      <li><code>download</code>
         <br>
         Download Unwetterkarten wÃ¤hrend des updates (0|1). 
         <br>
      </li>
      <li><code>savepath</code>
         <br>
         Pfad zum speichern der Karten (default: /tmp/). 
         <br>
      </li>
      <li><code>maps</code>
         <br>
         Leerzeichen separierte Liste der zu speichernden Karten. FÃ¼r mÃ¶gliche Karten siehe <code>NinaAsHtmlKarteLand</code>.
         <br>
      </li>
      <li><code>humanreadable</code>
         <br>
     Anzeige weiterer Readings Warn_?_Start_Date, Warn_?_Start_Time, Warn_?_End_Date, Warn_?_End_Time. Diese Readings enthalten aus dem Timestamp kalkulierte Datums/Zeit Angaben. Weiterhin werden folgende Readings aktivier: Warn_?_Type_Str und Warn_?_NinaLevel_Str welche den Unwettertyp als auch das Unwetter-Warn-Level als Text ausgeben. (0|1) 
         <br>
      </li>
      <li><code>lang</code>
         <br>
         Umschalten der angeforderten Sprache fÃ¼r kurz und lange warn text. (de|en|it|fr|es|..). 
         <br>
      </li>
      <li><code>sort_readings_by</code>
         <br>
         Sortierreihenfolge der Warnmeldungen. (start|severity|creation).
         <br>
      </li>
      <li><code>htmlsequence</code>
         <br>
         Anzeigereihenfolge der html warnungen. (ascending|descending). 
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
      <li><code>localiconbase</code>
         <br>
         BaseURL angeben um Warn Icons lokal zu hosten. (Dateityp ist png). 
         <br>
      </li>
      <li><code>intervalAtWarnLevel</code>
         <br>
         konfiguriert den Interval je nach WarnLevel. Beispiel: 2=1800,3=900,4=300
         <br>
      </li>

      <br>
   </ul>  

   <br>

   <a name="Ninareading"></a>
   <b>Readings</b>
   <ul>
      <br>
      <li><b>Warn_</b><i>0|1|2|3...|9</i><b>_...</b> - aktive Warnmeldungen</li>
      <li><b>WarnCount</b> - Anzahl der aktiven Warnmeldungen</li>
      <li><b>WarnNinaLevel</b> - Gesamt Warn Level </li>
      <li><b>WarnNinaLevel_Color</b> - Gesamt Warn Level Farbe</li>
      <li><b>WarnNinaLevel_Str</b> - Gesamt Warn Level Text</li>
      <li><b>Warn_</b><i>0</i><b>_AltitudeMin</b> - minimum HÃ¶he fÃ¼r Warnung </li>
      <li><b>Warn_</b><i>0</i><b>_AltitudeMax</b> - maximum HÃ¶he fÃ¼r Warnung </li>
      <li><b>Warn_</b><i>0</i><b>_EventID</b> - EventID der Warnung </li>
      <li><b>Warn_</b><i>0</i><b>_Creation</b> - Warnungs Erzeugung </li>
      <li><b>Warn_</b><i>0</i><b>_Creation_Date</b> - Warnungs Erzeugungs Datum </li>
      <li><b>Warn_</b><i>0</i><b>_Creation_Time</b> - Warnungs Erzeugungs Zeit </li>
      <li><b>currentIntervalMode</b> - default/warn, aktuell Verwendeter Interval. Internal INTERVAL oder INTERVALWARN</li>
      <li><b>Warn_</b><i>0</i><b>_Start</b> - Begin der Warnung</li>
      <li><b>Warn_</b><i>0</i><b>_Start_Date</b> - Startdatum der Warnung</li>
      <li><b>Warn_</b><i>0</i><b>_Start_Time</b> - Startzeit der Warnung</li>
      <li><b>Warn_</b><i>0</i><b>_End</b> - Warn Ende</li>
      <li><b>Warn_</b><i>0</i><b>_End_Date</b> - Enddatum der Warnung</li>
      <li><b>Warn_</b><i>0</i><b>_End_Time</b> - Endzeit der Warnung</li>
      <li><b>Warn_</b><i>0</i><b>_Severity</b> - Schwere des Unwetters (0 kein Unwetter, 12 massives Unwetter)</li>
      <li><b>Warn_</b><i>0</i><b>_Hail</b> - Hagelwarnung (1|0)</li>
      <li><b>Warn_</b><i>0</i><b>_Type</b> - Art des Unwetters</li>
      <li><b>Warn_</b><i>0</i><b>_Type_Str</b> - Art des Unwetters (text)</li>
      <ul>
        <li><b>1</b> - unbekannt</li>
        <li><b>2</b> - Sturm/Orkan</li>
        <li><b>3</b> - Schneefall</li>
        <li><b>4</b> - Regen</li>
        <li><b>5</b> - Extremfrost</li>
        <li><b>6</b> - Waldbrandgefahr</li>
        <li><b>7</b> - Gewitter</li>
        <li><b>8</b> - GlÃ¤tte</li>
        <li><b>9</b> - Hitze</li>
        <li><b>10</b> - Glatteisregen</li>
        <li><b>11</b> - Bodenfrost</li>
      </ul>
      <li><b>Warn_</b><i>0</i><b>_NinaLevel</b> - Unwetterwarnstufe (0-5)</li>
      <li><b>Warn_</b><i>0</i><b>_NinaLevel_Str</b> - Unwetterwarnstufe (text)</li>
      <li><b>Warn_</b><i>0</i><b>_levelName</b> - Level Warn Name</li>
      <li><b>Warn_</b><i>0</i><b>_ShortText</b> - Kurzbeschreibung der Warnung</li>
      <li><b>Warn_</b><i>0</i><b>_LongText</b> - AusfÃ¼hrliche Unwetterbeschreibung</li>
      <li><b>Warn_</b><i>0</i><b>_IconURL</b> - Kumulierte URL um Warnungs-Icon von <a href="http://www.unwetterzentrale.de">www.unwetterzentrale.de</a> anzuzeigen</li>
   </ul>
   <br>

   <a name="Ninaweblinks"></a>
   <b>Weblinks</b>
   <ul>
      <br>

      &Uuml;ber die Funktionen <code>NinaAsHtml, NinaAsHtmlLite, NinaAsHtmlFP, NinaAsHtmlKarteLand, NinaAsHtmlMovie</code> wird HTML-Code zur Warnanzeige und Wetterfilme Ã¼ber weblinks erzeugt.
      <br><br><br>
      Beispiele:
      <br>
      <li><code>define UnwetterDetailiert weblink htmlCode {NinaAsHtml("Nina_device")}</code></li>
      <br>
      <li><code>define UnwetterLite weblink htmlCode {NinaAsHtmlLite("Nina_device")}</code></li>
      <br>
      <li><code>define UnwetterFloorplan weblink htmlCode {NinaAsHtmlFP("Nina_device")}</code></li>
      <br>
      <li><code>define UnwetterKarteLand weblink htmlCode {NinaAsHtmlKarteLand("Nina_device","Bayern")}</code></li>
      <ul>        
        <li>Der zweite Parameter kann einer der folgenden sein:
        <ul>      
          <li>europa</li>
          <br/>
          <li>deutschland</li>
          <li>deutschland-small</li>
          <li>niedersachsen</li>
          <li>bremen</li>
          <li>bayern</li>
          <li>schleswig-holstein</li>
          <li>hamburg</li>
          <li>mecklenburg-vorpommern</li>
          <li>sachsen</li>
          <li>sachsen-anhalt</li>
          <li>nordrhein-westfalen</li>
          <li>thueringen</li>
          <li>rheinland-pfalz</li>
          <li>saarland</li>
          <li>baden-wuerttemberg</li>
          <li>hessen</li>
          <li>brandenburg</li>
          <li>berlin</li>
          <br/>
          <li>isobaren1</li>
          <li>isobaren2</li>
          <li>isobaren3</li>
        </ul>          
        </li>
      </ul>
      <li><code>define UnwetterKarteMovie weblink htmlCode {NinaAsHtmlMovie("Nina_device","niederschlag-wolken-de")}</code></li>
      <ul>
        <li>Der zweite Parameter kann einer der folgenden sein:
        <ul>
          <li>niederschlag-wolken</li>
          <li>stroemung</li>
          <li>temperatur</li>
          <br/>
          <li>niederschlag-wolken-de</li>
          <li>stroemung-de</li>
          <br/>
          <li>niederschlag-wolken-ch</li>
          <li>stroemung-ch</li>
          <br/>
          <li>niederschlag-wolken-at</li>
          <li>stroemung-at</li>
          <br/>
          <li>neerslag-wolken-nl</li>
          <li>stroming-nl</li>
          <br/>
          <li>nuages-precipitations-fr</li>
          <li>courants-fr</li>
          <br/>
          <li>clouds-precipitation-uk</li>
          <li>currents-uk</li>
          <br/>
        </ul>          
        </li>
      </ul>


      <br/><br/>
   </ul>
   <br>
 

</ul>

=end html_DE
=cut
