####################################################################################################
#
#  77_MoWaS.pm
#
#  (c) 2019 K�lnsolar
#
#  Special thanks goes to comitters:
#       - Marko Oldenburg (leongaultier at gmail dot com)
#  
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
#  +*00:00:05 {fhem("define MoWaS_device MoWaS DE 50997 1200")}
# keine korrekte Neuanlage bei defmod(bsp. URL)
#
#  $Id: 77_MoWaS.pm 17646 2018-10-30 11:20:16Z K�lnsolar $
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
my @DEmonths = ( "Januar","Februar","März","April","Mai","Juni","Juli","August","September","Oktober","November","Dezember");
my @ENweekdays = qw(sunday monday thuesday wednesday thursday friday saturday);
my @ENmonths = ("January","February","March","April","Mäy","June","July","August","September","October","November","December");

my $MODUL           = "MoWaS";
my $version         = "0.0.1";

# Declare functions
sub MoWaS_Log($$$);
#sub MoWaS_Map2Movie($$);
#sub MoWaS_Map2Image($$);
#sub MoWaS_Initialize($);
#sub MoWaS_Define($$);
#sub MoWaS_Undef($$);
#sub MoWaS_Set($@);
#sub MoWaS_Get($@);
#sub MoWaS_GetCurrent($@);
#sub MoWaS_GetCurrentHail($);
#sub MoWaS_JSONAcquire($$);
#sub MoWaS_Start($);
#sub MoWaS_Aborted($);
#sub MoWaS_Done($);
#sub MoWaS_Run($);
#sub MoWaSAsHtml($;$);
#sub MoWaSAsHtmlLite($;$);
#sub MoWaSAsHtmlFP($;$);
#sub MoWaSAsHtmlMovie($$);
#sub MoWaSAsHtmlKarteLand($$);
#sub MoWaS_GetSeverityColor($$);
#sub MoWaS_GetMoWaSLevel($$);
#sub MoWaSSearchLatLon($$);
#sub MoWaSSearchAreaID($$);
#sub MoWaS_IntervalAtWarnLevel($);




my $countrycode = "DE";
my $geocode = "05315";
my $MoWaS_alert_url = "http://feed.alertspro.meteogroup.com/AlertsPro/AlertsProPollService.php?method=getWarning&language=de&areaID=UWZ" . $countrycode . $geocode;

sub MoWaS_Initialize($) {

    my ($hash) = @_;
    $hash->{DefFn}    = "MoWaS_Define";
    $hash->{UndefFn}  = "MoWaS_Undef";
    $hash->{SetFn}    = "MoWaS_Set";
    $hash->{GetFn}    = "MoWaS_Get";
    $hash->{AttrList} = "download:0,1 ".
                        "savepath ".
                        "maps ".
#                        "humanreadable:0,1 ".
                        "htmlattr ".
                        "htmltitle ".
                        "htmltitleclass ".
                        "htmlsequence:ascending,descending ".
                        "lang ".
                        "sort_readings_by:severity,sent,creation ".
                        "localiconbase ".
#                        "intervalAtWarnLevel ".
                        "disable:1 ".
                        $readingFnAttributes;
   
    foreach my $d(sort keys %{$modules{MoWaS}{defptr}}) {
        my $hash = $modules{MoWaS}{defptr}{$d};
        $hash->{VERSION}      = $version;
    }
}

###################################
sub MoWaS_Define($$) {

    my ( $hash, $def ) = @_;
    my $name = $hash->{NAME};
    my $lang = "";
    my @a    = split( "[ \t][ \t]*", $def );
   
    return "Error: Perl moduls ".$missingModul."are missing on this system" if( $missingModul );
    return "Wrong syntax: use define <name> MoWaS <CountryCode> <geocode> <Interval> "  if (int(@a) != 5 and  ((lc $a[2]) ne "search"));

    if ((lc $a[2]) ne "search") {

        $hash->{STATE}           = "Initializing";
        $hash->{CountryCode}     = $a[2];
        $hash->{geocode}         = $a[3];
        
        ## URL by CountryCode

        my $URL_language="en";
        if ( $hash->{CountryCode} ~~ [ 'DE' ] ) {
            $URL_language="de";
        }
        
#        $hash->{URL} =  "http://feed.alertspro.meteogroup.com/AlertsPro/AlertsProPollService.php?method=getWarning&language=" . $URL_language . "&areaID=UWZ" . $a[2] . $a[3];
        $hash->{URL} =  "	";    
        
        $hash->{fhem}{LOCAL}    = 0;
        $hash->{INTERVAL}       = $a[4];
        $hash->{INTERVALWARN}   = 0;
        $hash->{VERSION}        = $version;
       
        RemoveInternalTimer($hash);
       
        #Get first data after 12 seconds
        InternalTimer( gettimeofday() + 12, "MoWaS_Start", $hash, 0 );

    }
    
    $modules{MoWaS}{defptr}{$hash->{geocode}} = $hash;
    
    return undef;
}

#####################################
sub MoWaS_Undef($$) {

    my ( $hash, $arg ) = @_;

    RemoveInternalTimer( $hash );
    BlockingKill( $hash->{helper}{RUNNING_PID} ) if ( defined( $hash->{helper}{RUNNING_PID} ) );
    
    delete($modules{MoWaS}{defptr}{$hash->{geocode}});
    
    return undef;
}

#####################################
sub MoWaS_Set($@) {

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
            MoWaS_Log $hash, 4, "set command: " . $a[1];
            $hash->{fhem}{LOCAL} = 1;
            MoWaS_Start($hash);
            $hash->{fhem}{LOCAL} = 0;
        }
        
        default
        {
            return $usage;
        }
    }
    
    return;
}

sub MoWaS_Get($@) {

    my ( $hash, @a ) = @_;
    my $name    = $hash->{NAME};
   
    if ( $hash->{CountryCode} ~~ [ 'DE' ] ) {
        my $usage   = "Unknown argument $a[1], choose one of Sturm:noArg Schneefall:noArg Regen:noArg Extremfrost:noArg Waldbrand:noArg Gewitter:noArg Glaette:noArg Hitze:noArg Glatteisregen:noArg Bodenfrost:noArg Hagel:noArg ";
     
        return $usage if ( @a < 2 );
       
        if    ($a[1] =~ /^Sturm/)            { MoWaS_GetCurrent($hash,2); }
        elsif ($a[1] =~ /^Schneefall/)       { MoWaS_GetCurrent($hash,3); }
        elsif ($a[1] =~ /^Regen/)            { MoWaS_GetCurrent($hash,4); }
        elsif ($a[1] =~ /^Extremfrost/)      { MoWaS_GetCurrent($hash,5); }
        elsif ($a[1] =~ /^Waldbrand/)        { MoWaS_GetCurrent($hash,6); }
        elsif ($a[1] =~ /^Gewitter/)         { MoWaS_GetCurrent($hash,7); }
        elsif ($a[1] =~ /^Glaette/)          { MoWaS_GetCurrent($hash,8); }
        elsif ($a[1] =~ /^Hitze/)            { MoWaS_GetCurrent($hash,9); }
        elsif ($a[1] =~ /^Glatteisregen/)    { MoWaS_GetCurrent($hash,10); }
        elsif ($a[1] =~ /^Bodenfrost/)       { MoWaS_GetCurrent($hash,11); }
        elsif ($a[1] =~ /^Hagel/)            { MoWaS_GetCurrentHail($hash); }
        else                                 { return $usage; }
    } else {
        my $usage   = "Unknown argument $a[1], choose one of storm:noArg snow:noArg rain:noArg extremfrost:noArg forest-fire:noArg thunderstorms:noArg glaze:noArg heat:noArg glazed-rain:noArg soil-frost:noArg hail:noArg ";
        
        return $usage if ( @a < 2 );
    
        if    ($a[1] =~ /^storm/)            { MoWaS_GetCurrent($hash,2); }
        elsif ($a[1] =~ /^snow/)             { MoWaS_GetCurrent($hash,3); }
        elsif ($a[1] =~ /^rain/)             { MoWaS_GetCurrent($hash,4); }
        elsif ($a[1] =~ /^extremfrost/)      { MoWaS_GetCurrent($hash,5); }
        elsif ($a[1] =~ /^forest-fire/)      { MoWaS_GetCurrent($hash,6); }
        elsif ($a[1] =~ /^thunderstorms/)    { MoWaS_GetCurrent($hash,7); }
        elsif ($a[1] =~ /^glaze/)            { MoWaS_GetCurrent($hash,8); }
        elsif ($a[1] =~ /^heat/)             { MoWaS_GetCurrent($hash,9); }
        elsif ($a[1] =~ /^glazed-rain/)      { MoWaS_GetCurrent($hash,10); }
        elsif ($a[1] =~ /^soil-frost/)       { MoWaS_GetCurrent($hash,11); }
        elsif ($a[1] =~ /^hail/)             { MoWaS_GetCurrentHail($hash); }
        else                                 { return $usage; }

    }
}

###################################
#####################################
sub MoWaS_GetCurrent($@) {

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
sub MoWaS_GetCurrentHail($) {

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
sub MoWaS_Start($) {

    my ($hash) = @_;
    my $name   = $hash->{NAME};
   
    return unless (defined($hash->{NAME}));
   
    if(!$hash->{fhem}{LOCAL} && $hash->{INTERVAL} > 0) {        # set up timer if automatically call
        RemoveInternalTimer( $hash );
        InternalTimer(gettimeofday() + $hash->{INTERVAL}, "MoWaS_Start", $hash, 1 );
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
        MoWaS_Log $hash, 3, "missing URL";
        return;
    }
  
    $hash->{helper}{RUNNING_PID} = BlockingCall( 
			            "MoWaS_Run",          # callback worker task
			            $name,              # name of the device
			            "MoWaS_Done",         # callback result method
			            120,                # timeout seconds
			            "MoWaS_Aborted",      #  callback for abortion
			            $hash );            # parameter for abortion
}


#####################################
sub MoWaS_Run($) {

    my ($name) = @_;
    my $ptext=$name;
    my $MoWaS_download;
    my $MoWaS_savepath;
    my $MoWaS_humanreadable;
    my $message;
    my $i=0;
    
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
        $MoWaS_download = 0;
    } else {
        $MoWaS_download = $attrdownload;
    }
    
    # preset savepath
    if ($attrsavepath eq "") {
        $MoWaS_savepath = "/tmp/";
    } else {
        $MoWaS_savepath = $attrsavepath;
    }
    
    # preset humanreadable
    if ($attrhumanreadable eq "") {
        $MoWaS_humanreadable = 0;
    } else {
      $MoWaS_humanreadable = $attrhumanreadable;
    }

    if ( $MoWaS_download == 1 ) {
        if ( ! defined($maps2fetch) ) { $maps2fetch = "deutschland"; }
            MoWaS_Log $hash, 4, "Maps2Fetch : ".$maps2fetch;
            my @maps = split(' ', $maps2fetch);
            my $MoWaS_de_url = "http://www.unwetterzentrale.de/images/map/";
            foreach my $smap (@maps) {
                MoWaS_Log $hash, 4, "Download map : ".$smap;
                my $img = MoWaS_Map2Image($hash,$smap);
                if (!defined($img) ) { $img=$MoWaS_de_url.'deutschland_index.png'; }
                my $code = getstore($img, $MoWaS_savepath.$smap.".png");        
                if($code == 200) {
                    MoWaS_Log $hash, 4, "Successfully downloaded map ".$smap;
                } else {
                    MoWaS_Log $hash, 3, "Failed to download map (".$img.")";
            	}
       	} 
    }

    my ($MoWaS_warnings, @MoWaS_records, $enc) = "";

    # acquire the json-response
    my $response = MoWaS_JSONAcquire($hash,$hash->{URL}); 					     # MoWaS-Meldungen
#    my $response = MoWaS_JSONAcquire($hash,"http://feed.alertspro.meteogroup.com/AlertsPro/AlertsProPollService.php?method=getWarning&language=de&areaID=UWZDE39517"); 
    if (substr($response,0,5) ne "Error") {
    MoWaS_Log $hash, 5, length($response)." characters captured from MoWaS:  ".$response;
    $MoWaS_warnings = JSON->new->ascii->decode($response);
    @MoWaS_records = @{$MoWaS_warnings};
    }
    else {
	$message .= $response;
    }

    my $response = MoWaS_JSONAcquire($hash,"https://warnung.bund.de/bbk.katwarn/warnmeldungen.json"); 	# Katwarn-Meldungen
    if (substr($response,0,5) ne "Error") {
    MoWaS_Log $hash, 5, length($response)." characters captured from MoWaS:  ".$response;
    $MoWaS_warnings = JSON->new->ascii->decode($response);
   foreach my $element (@{$MoWaS_warnings}) {
        push @MoWaS_records, $element;
    }
    }
    else {
	$message .= $response;
    } 

   my $response = MoWaS_JSONAcquire($hash,"https://warnung.bund.de/bbk.biwapp/warnmeldungen.json"); 	# BIWAPP-Meldungen
    	$response =~ s/\\u/ /g; 
    if (substr($response,0,5) ne "Error") {
    MoWaS_Log $hash, 5, length($response)." characters captured from MoWaS:  ".$response;
    $MoWaS_warnings = JSON->new->ascii->decode($response);
   foreach my $element (@{$MoWaS_warnings}) {
        push @MoWaS_records, $element;
    }
    }
    else {
	$message .= $response;
    } 
    return "$name|$message" if (defined($message));
     $MoWaS_warnings = \@MoWaS_records;
#use Data::Dumper;
#    MoWaS_Log $hash, 4, "MoWaS after decoding ".Dumper($MoWaS_warnings);
#    print "All warnings after decoding ".@MoWaS_records;
     $enc = guess_encoding($MoWaS_warnings);
#    MoWaS_Log $hash, 4, "MoWaS $enc";

    my $MoWaS_warncount = scalar(@{$MoWaS_warnings});
    MoWaS_Log $hash, 4, "There are ".scalar(@{$MoWaS_warnings})." warning records active";
    my $sortby = AttrVal( $name, 'sort_readings_by',"" );
    my @sorted;
    
    if ( $sortby eq "creation" ) {
        MoWaS_Log $hash, 4, "Sorting by creation";
        @sorted =  sort { $b->{sent} <=> $a->{sent} } @{ $MoWaS_warnings };
    } elsif ( $sortby ne "severity" ) {
        MoWaS_Log $hash, 4, "Sorting by sent";
        @sorted =  sort { $b->{sent} cmp $a->{sent} } @{ $MoWaS_warnings };
    } else {
        MoWaS_Log $hash, 4, "Sorting by severity";
        @sorted =  sort { $a->{severity} <=> $b->{severity} } @{ $MoWaS_warnings };
    }

    
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

    my @MoWaSmaxlevel;
    foreach my $single_warning (@sorted) {
       MoWaS_Log $hash, 3, "Record with geocode: ".$single_warning->{'info'}[0]{'area'}[0]{'geocode'}[0]{'value'}." Sender: ".$single_warning->{'sender'};
	if (substr($single_warning->{'info'}[0]{'area'}[0]{'geocode'}[0]{'value'},0,5) eq $hash->{geocode}) {
#        push @MoWaSmaxlevel, MoWaS_GetMoWaSLevel($hash,$single_warning->{'urgency'});
 	$message .= content($hash,"_EventID",$single_warning->{'identifier'},$i) if (defined($single_warning->{'identifier'})); 
 	$message .= content($hash,"_Creation",$single_warning->{'sent'},$i) if (defined($single_warning->{'sent'})); 
 	$message .= content($hash,"_Sender",$single_warning->{'sender'},$i) if (defined($single_warning->{'sender'})); 
 	$message .= content($hash,"_Severity",$single_warning->{'info'}[0]{'severity'},$i) if (defined($single_warning->{'info'}[0]{'severity'})); 
 	$message .= content($hash,"_End",$single_warning->{'info'}[0]{'expires'},$i) if (defined($single_warning->{'info'}[0]{'expires'})); 
 	$message .= content($hash,"_Event",$single_warning->{'info'}[0]{'event'},$i) if (defined($single_warning->{'info'}[0]{'event'})); 

 	MoWaS_Log $hash, 2, "Warn_".$i."_status: ".$single_warning->{'status'} if (defined($single_warning->{'status'}) && $single_warning->{'status'} ne "Actual"); 
 	MoWaS_Log $hash, 2, "Warn_".$i."_scope: ".$single_warning->{'scope'} if (defined($single_warning->{'scope'}) && $single_warning->{'scope'} ne "Public"); 
 	MoWaS_Log $hash, 2, "Warn_".$i."_msgType: ".$single_warning->{'msgType'} if (defined($single_warning->{'msgType'}) && $single_warning->{'msgType'} ne "Alert" && $single_warning->{'msgType'} ne "Cancel"); 
 	MoWaS_Log $hash, 2, "Warn_".$i."_certainty: ".$single_warning->{'info'}[0]{'certainty'} if (defined($single_warning->{'info'}[0]{'certainty'}) && $single_warning->{'info'}[0]{'certainty'} ne "Observed" && $single_warning->{'info'}[0]{'certainty'} ne "Unknown"); 
 	MoWaS_Log $hash, 2, "Warn_".$i."_category: ".$single_warning->{'info'}[0]{'category'}[0] if (defined($single_warning->{'info'}[0]{'category'}[0]) && $single_warning->{'info'}[0]{'category'}[0] ne "Safety" && $single_warning->{'info'}[0]{'category'}[0] ne "Other"); 
 	MoWaS_Log $hash, 2, "Warn_".$i."_urgency: ".$single_warning->{'info'}[0]{'urgency'} if (defined($single_warning->{'info'}[0]{'urgency'}) && $single_warning->{'info'}[0]{'urgency'} ne "Immediate" && $single_warning->{'info'}[0]{'urgency'} ne "Unknown"); 

#        MoWaS_Log $hash, 4, "Warn_".$i."_levelName: ".$single_warning->{'payload'}{'levelName'};
#        $message .= "Warn_".$i."_levelName|".$single_warning->{'payload'}{'levelName'}."|";

        my $uclang = "EN";
        if (AttrVal( $name, 'lang',undef) ) {
            $uclang = uc AttrVal( $name, 'lang','');
        } else {
            # Begin Language by AttrVal
            if ( $hash->{CountryCode} ~~ [ 'DE' ] ) {
                $uclang = "DE";
            } else {
                $uclang = "EN";
            }
        }

 	$message .= content($hash,"_Contact",$single_warning->{'info'}[0]{'contact'},$i) if (defined($single_warning->{'info'}[0]{'contact'})); 
	$message .= content($hash,"_Area",$single_warning->{'info'}[0]{'area'}[0]{'areaDesc'},$i) if (defined($single_warning->{'info'}[0]{'area'}[0]{'areaDesc'})); 
	$message .= content($hash,"_Instruction",$single_warning->{'info'}[0]{'instruction'},$i) if (defined($single_warning->{'info'}[0]{'instruction'})); 
	$message .= content($hash,"_ShortText",$single_warning->{'info'}[0]{'headline'},$i) if (defined($single_warning->{'info'}[0]{'headline'})); 
	$message .= content($hash,"_LongText",$single_warning->{'info'}[0]{'description'},$i) if (defined($single_warning->{'info'}[0]{'description'})); 
	$message .= content($hash,"_Sendername",$single_warning->{'info'}[0]{'parameter'}[0]{'value'},$i) if (defined($single_warning->{'info'}[0]{'parameter'}[0]{'value'})); 

        $i++;
    }
    }

    $message .= "durationFetchReadings|";
    $message .= sprintf "%.2f",  time() - $readingStartTime;
    $message =~ s/\n/ /g; 

    MoWaS_Log $hash, 3, "Done fetching data with ".$i." warnings active";
    MoWaS_Log $hash, 4, "Will return : "."$name|$message|WarnCount|$i" ;
    
    return "$name|$message|WarnCount|$i" ;
}

#####################################
# asyncronous callback by blocking
sub content($$$$) {

	my ($hash,$field,$value,$i) = @_;

        
        MoWaS_Log $hash, 4, "Warn_".$i.$field.": ".$value;
	return "Warn_".$i.$field."|".$value."|";
	
}

#####################################
# asyncronous callback by blocking
sub MoWaS_Done($) {
    MoWaS_Log "MoWaS", 5, "Beginning processing of selected data.";
    my ($string) = @_;
    return unless ( defined($string) );
   
    # all term are separated by "|" , the first is the name of the instance
    my ( $name, %values ) = split( "\\|", $string );
    my $hash = $defs{$name};
    return unless ( defined($hash->{NAME}) );
   
    # delete the marker for RUNNING_PID process
    delete( $hash->{helper}{RUNNING_PID} );  
    
    # UnWetterdaten speichern
    readingsBeginUpdate($hash);
    MoWaS_Log $hash, 5, "Starting Readings Update.";

    if ( defined $values{Error} ) {
        readingsBulkUpdate( $hash, "lastConnection", $values{Error} );
    } else {
        while (my ($rName, $rValue) = each(%values) ) {
            readingsBulkUpdate( $hash, $rName, $rValue );
            MoWaS_Log $hash, 5, "reading:$rName value:$rValue";
        }
        if (keys %values > 0) {
            my $newState;
            MoWaS_Log $hash, 4, "Delete old Readings"; 
            for my $Counter ($values{WarnCount} .. 9) {
                CommandDeleteReading(undef, "$hash->{NAME} Warn_${Counter}_.*");
            }
            if (defined $values{WarnCount}) {
                # Message by CountryCode
                $newState = "Warnings: " . $values{WarnCount};
                $newState = "Warnungen: " . $values{WarnCount} if ( $hash->{CountryCode} ~~ [ 'DE' ] );
                # end Message by CountryCode
            } else {
                $newState = "Error: Could not capture all data. Please check CountryCode and geocode.";
            }
            readingsBulkUpdate($hash, "state", $newState);
            readingsBulkUpdate( $hash, "lastConnection", keys( %values )." values captured in ".$values{durationFetchReadings}." s" );
            MoWaS_Log $hash, 4, keys( %values )." values captured";
        } else {
	    readingsBulkUpdate( $hash, "lastConnection", "no data found" );
            MoWaS_Log $hash, 1, "No data found. Check city name or URL.";
        }
    }
    
    readingsEndUpdate( $hash, 1 );
    
    if( AttrVal($name,'intervalAtWarnLevel','') ne '' and ReadingsVal($name,'WarnMoWaSLevel',0) > 1 ) {#
#        MoWaS_IntervalAtWarnLevel($hash);
        MoWaS_Log $hash, 5, "run Sub IntervalAtWarnLevel"; 
    }
}

#####################################
sub MoWaS_Aborted($) {

    my ($hash) = @_;
    delete( $hash->{helper}{RUNNING_PID} );
}


#####################################
sub MoWaS_JSONAcquire($$) {

    my ($hash, $URL)  = @_;
    my $name    = $hash->{NAME};
    
    return unless (defined($hash->{NAME}));
 
    MoWaS_Log $hash, 4, "Start capturing of $URL";

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
        MoWaS_Log $hash, 1, "Error: $err_log";
        return "Error|Error " . $err;
    }

    MoWaS_Log $hash, 4, length($data)." characters captured:  $data";
    return $data;
}
########################################
sub MoWaS_Log($$$) {

    my ( $hash, $loglevel, $text ) = @_;
    my $xline       = ( caller(0) )[2];

    my $xsubroutine = ( caller(1) )[3];
    my $sub         = ( split( ':', $xsubroutine ) )[2];
    $sub =~ s/MoWaS_//;

    my $instName = ( ref($hash) eq "HASH" ) ? $hash->{NAME} : $hash;
    Log3 $instName, $loglevel, "$MODUL $instName: $sub.$xline " . $text;
}

########################################
sub MoWaS_Map2Movie($$) {
    my $MoWaS_movie_url = "http://www.meteocentrale.ch/uploads/media/";
    my ( $hash, $smap ) = @_;
    my $lmap;

    $smap=lc($smap);

    ## Euro
    $lmap->{'niederschlag-wolken'}=$MoWaS_movie_url.'MoWaS_EUROPE_COMPLETE_niwofi.mp4';
    $lmap->{'stroemung'}=$MoWaS_movie_url.'MoWaS_EUROPE_COMPLETE_stfi.mp4';
    $lmap->{'temperatur'}=$MoWaS_movie_url.'MoWaS_EUROPE_COMPLETE_theta_E.mp4';

    ## DE
    $lmap->{'niederschlag-wolken-de'}=$MoWaS_movie_url.'MoWaS_EUROPE_GERMANY_COMPLETE_niwofi.mp4';
    $lmap->{'stroemung-de'}=$MoWaS_movie_url.'MoWaS_EUROPE_GERMANY_COMPLETE_stfi.mp4';

    return $lmap->{$smap};
}

########################################
sub MoWaS_Map2Image($$) {

    my $MoWaS_de_url = "http://www.unwetterzentrale.de/images/map/";

    my ( $hash, $smap ) = @_;
    my $lmap;
    
    $smap=lc($smap);

    ## Euro
    $lmap->{'europa'}=$MoWaS_de_url.'europe_index.png';

    ## DE
    $lmap->{'deutschland'}=$MoWaS_de_url.'deutschland_index.png';
    $lmap->{'deutschland-small'}=$MoWaS_de_url.'deutschland_preview.png';
    $lmap->{'niedersachsen'}=$MoWaS_de_url.'niedersachsen_index.png';
    $lmap->{'bremen'}=$MoWaS_de_url.'niedersachsen_index.png';
    $lmap->{'bayern'}=$MoWaS_de_url.'bayern_index.png';
    $lmap->{'schleswig-holstein'}=$MoWaS_de_url.'schleswig_index.png';
    $lmap->{'hamburg'}=$MoWaS_de_url.'schleswig_index.png';
    $lmap->{'mecklenburg-vorpommern'}=$MoWaS_de_url.'meckpom_index.png';
    $lmap->{'sachsen'}=$MoWaS_de_url.'sachsen_index.png';
    $lmap->{'sachsen-anhalt'}=$MoWaS_de_url.'sachsenanhalt_index.png';
    $lmap->{'nordrhein-westfalen'}=$MoWaS_de_url.'nrw_index.png';
    $lmap->{'thueringen'}=$MoWaS_de_url.'thueringen_index.png';
    $lmap->{'rheinland-pfalz'}=$MoWaS_de_url.'rlp_index.png';
    $lmap->{'saarland'}=$MoWaS_de_url.'rlp_index.png';
    $lmap->{'baden-wuerttemberg'}=$MoWaS_de_url.'badenwuerttemberg_index.png';
    $lmap->{'hessen'}=$MoWaS_de_url.'hessen_index.png';
    $lmap->{'brandenburg'}=$MoWaS_de_url.'brandenburg_index.png';
    $lmap->{'berlin'}=$MoWaS_de_url.'brandenburg_index.png';

    ## Isobaren
    $lmap->{'isobaren1'}="http://www.unwetterzentrale.de/images/icons/MoWaS_ISO_00.jpg";
    $lmap->{'isobaren2'}="http://www.wetteralarm.at/uploads/pics/MoWaS_EURO_ISO_GER_00.jpg";
    $lmap->{'isobaren3'}="http://www.severe-weather-centre.co.uk/uploads/pics/MoWaS_EURO_ISO_ENG_00.jpg";

    return $lmap->{$smap};
}

#####################################
sub MoWaSAsHtml($;$) {

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
                $ret .= '<tr><td class="MoWaSIcon" style="vertical-align:top;"><img src="'.ReadingsVal($name, "Warn_".$i."_IconURL", "").'"></td>';
                $ret .= '<td class="MoWaSValue"><b>'.ReadingsVal($name, "Warn_".$i."_ShortText", "").'</b><br><br>';
                $ret .= ReadingsVal($name, "Warn_".$i."_LongText", "").'<br><br>';
                my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(ReadingsVal($name, "Warn_".$i."_Start", ""));
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
                ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(ReadingsVal($name, "Warn_".$i."_End", ""));
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
                $ret .= '<tr><td class="MoWaSIcon" style="vertical-align:top;"><img src="'.ReadingsVal($name, "Warn_".$i."_IconURL", "").'"></td>';
                $ret .= '<td class="MoWaSValue"><b>'.ReadingsVal($name, "Warn_".$i."_ShortText", "").'</b><br><br>';
                $ret .= ReadingsVal($name, "Warn_".$i."_LongText", "").'<br><br>';
                my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(ReadingsVal($name, "Warn_".$i."_Start", ""));
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
                ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(ReadingsVal($name, "Warn_".$i."_End", ""));
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
        $ret .= '<tr><td class="MoWaSIcon" style="vertical-align:top;">';
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
sub MoWaSAsHtmlLite($;$) {

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
                $ret .= '<tr><td class="MoWaSIcon" style="vertical-align:top;"><img src="'.ReadingsVal($name, "Warn_".$i."_IconURL", "").'"></td>';
                $ret .= '<td class="MoWaSValue"><b>'.ReadingsVal($name, "Warn_".$i."_ShortText", "").'</b><br><br>';
                my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(ReadingsVal($name, "Warn_".$i."_Start", ""));
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
                ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(ReadingsVal($name, "Warn_".$i."_End", ""));
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
                $ret .= '<tr><td class="MoWaSIcon" style="vertical-align:top;"><img src="'.ReadingsVal($name, "Warn_".$i."_IconURL", "").'"></td>';
                $ret .= '<td class="MoWaSValue"><b>'.ReadingsVal($name, "Warn_".$i."_ShortText", "").'</b><br><br>';
                my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(ReadingsVal($name, "Warn_".$i."_Start", ""));
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
                ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(ReadingsVal($name, "Warn_".$i."_End", ""));
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
        $ret .= '<tr><td class="MoWaSIcon" style="vertical-align:top;">';
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
sub MoWaSAsHtmlFP($;$) {

    my ($name,$items) = @_;
    my $tablewidth = ReadingsVal($name, "WarnCount", "") * 80;
    my $htmlsequence = AttrVal($name, "htmlsequence", "none");
    my $htmltitle = AttrVal($name, "htmltitle", "");
    my $htmltitleclass = AttrVal($name, "htmltitleclass", "");
    my $ret = '';
    
    $ret .= '<table class="MoWaS-fp" style="width:'.$tablewidth.'px"><tr><th class="'.$htmltitleclass.'" colspan="'.ReadingsVal($name, "WarnCount", "none").'">'.$htmltitle.'</th></tr>';
    $ret .= "<tr>";
    
    if ($htmlsequence eq "descending") {
        for ( my $i=ReadingsVal($name, "WarnCount", "")-1; $i>=0; $i--){
            $ret .= '<td class="MoWaSIcon"><img width="80px" src="'.ReadingsVal($name, "Warn_".$i."_IconURL", "").'"></td>';
        }
    } else {
        for ( my $i=0; $i<ReadingsVal($name, "WarnCount", ""); $i++){
            $ret .= '<td class="MoWaSIcon"><img width="80px" src="'.ReadingsVal($name, "Warn_".$i."_IconURL", "").'"></td>';
        }
    } 
    $ret .= "</tr>";
    $ret .= '</table>';

    return $ret;
}

#####################################
sub MoWaSAsHtmlMovie($$) {

    my ($name,$land) = @_;
    my $url = MoWaS_Map2Movie($name,$land);
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
sub MoWaSAsHtmlKarteLand($$) {

    my ($name,$land) = @_;
    my $url = MoWaS_Map2Image($name,$land);
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
sub MoWaS_GetSeverityColor($$) {
    my ($name,$MoWaSlevel) = @_;
    my $alertcolor       = "";

    my %MoWaSSeverity = ( "0" => "gruen",
                            "1" => "orange",
                            "2" => "gelb",
                            "3" => "orange",
                            "4" => "rot",
                            "5" => "violett");

    return $MoWaSSeverity{$MoWaSlevel};
}

#####################################
sub MoWaS_GetMoWaSLevel($$) {
    my ($name,$warnname) = @_;
    my @alert            = split(/_/,$warnname);

    if ( $alert[0] eq "notice" ) {
        return "1";
    } elsif ( $alert[1] eq "forewarn" ) {
        return "2";
    } else {
        my %MoWaSSeverity = ( "green" => "0",
                            "yellow" => "2",
                            "orange" => "3",
                            "red" => "4",
                            "violet" => "5");
        return $MoWaSSeverity{$alert[2]};
    }
}

#####################################
sub MoWaS_IntervalAtWarnLevel($) {

    my $hash        = shift;
    
    my $name        = $hash->{NAME};
    my $warnLevel   = ReadingsVal($name,'WarnMoWaSLevel',0);
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
        InternalTimer(gettimeofday() + $hash->{INTERVALWARN}, "MoWaS_Start", $hash, 1 );
        MoWaS_Log $hash, 4, "restart internal timer with interval $hash->{INTERVALWARN}";
    } else {
        RemoveInternalTimer( $hash );
        InternalTimer(gettimeofday() + $hash->{INTERVALWARN}, "MoWaS_Start", $hash, 1 );
        MoWaS_Log $hash, 4, "restart internal timer with interval $hash->{INTERVALWARN}";
    }
}

#####################################
##
##      MoWaS Helper Functions
##
#####################################

sub MoWaSSearchLatLon($$) {

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

    my $MoWaSxmlparser = XML::Simple->new();
    #my $xmlres = $parser->XMLin(
    my $search = ""; #$MoWaSxmlparser->XMLin($response->content, KeyAttr => { city => 'id' }, ForceArray => [ 'city' ]);

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
sub MoWaSSearchAreaID($$) {
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

    if ( $AreaType eq "MoWaS" ) {
        my $ret = '<html>Please use the following statement to define Unwetterzentrale for your location:<br /><br />';
        $ret   .= '<table width=100%><tr><td>';
        $ret   .= '<table class="block wide">';
        $ret   .= '<tr class="even">';
        $ret   .= "<td height=100><center><b>define Unwetterzentrale MoWaS $CC $AreaID 3600</b></center></td>";
        $ret   .= '</tr>';
        $ret   .= '</table>';
        $ret   .= '</td></tr></table>';
    
        $ret   .= '<br />';
        $ret   .= 'You can also use weblinks to add weathermaps. For a list of possible Weblinks see Commandref. For example to add the Europe Map use:<br />';
    
        $ret   .= '<table width=100%><tr><td>';
        $ret   .= '<table class="block wide">';
        $ret   .= '<tr class="even">';
        $ret   .= "<td height=100><center>define MoWaS_Map_Europe weblink htmlCode { MoWaSAsHtmlKarteLand('Unwetterzentrale','europa') }</center></td>";
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
=item summary       extracts thunderstorm warnings from unwetterzentrale.de
=item summary_DE    extrahiert Unwetterwarnungen von unwetterzentrale.de

=begin html

<a name="MoWaS"></a>
<h3>MoWaS</h3>
<ul>
   <a name="MoWaSdefine"></a>
   This modul extracts thunderstorm warnings from <a href="http://www.unwetterzentrale.de">www.unwetterzentrale.de</a>.
   <br/>
   Therefore the same interface is used as the Android App <a href="http://www.alertspro.com">Alerts Pro</a> does.
   A maximum of 10 thunderstorm warnings will be served.
   Additional the module provides a few functions to create HTML-Templates which can be used with weblink.
   <br>
   <i>The following Perl-Modules are used within this module: JSON, Encode::Guess </i>.
   <br/><br/>
   <b>Define</b>
   <ul>
      <br>
      <code>define &lt;Name&gt; MoWaS [CountryCode] [AreaID] [INTERVAL]</code>
      <br><br><br>
      Example:
      <br>
      <code>
        define MoWaS_device MoWaS DE 08357 1800<br>
        attr MoWaS_device download 1<br>
        attr MoWaS_device humanreadable 1<br>
        attr MoWaS_device maps eastofengland unitedkingdom<br><br>
        define UnwetterDetails weblink htmlCode {MoWaSAsHtml("MoWaS_device")}<br>
        define UnwetterMapE_UK weblink htmlCode {MoWaSAsHtmlKarteLand("MoWaS_device","eastofengland")}<br>
        define UnwetterLite weblink htmlCode {MoWaSAsHtmlLite("MoWaS_device")}
        define UnwetterMovie weblink htmlCode {MoWaSAsHtmlMovie("MoWaS_device","clouds-precipitation-uk")}
      </code>
      <br>&nbsp;

      <li><code>[CountryCode]</code>
         <br>
         Possible values: DE<br/>
      </li><br>
      <li><code>[AreaID]</code>
         <br>
         For Germany you can use the postalcode. 
         <br>
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

   <a name="MoWaSget"></a>
   <b>Get</b>
   <ul>
      <br>
      <li><code>get &lt;name&gt; soil-frost</code>
         <br>
         give info about current soil frost (active|inactive).
      </li><br>
      <li><code>get &lt;name&gt; extremfrost</code>
         <br>
         give info about current frost (active|inactive).
      </li><br>
      <li><code>get &lt;name&gt; thunderstorm</code>
         <br>
         give info about current thunderstorm (active|inactive).
      </li><br>
      <li><code>get &lt;name&gt; glaze</code>
         <br>
         give info about current glaze (active|inactive).
      </li><br>
      <li><code>get &lt;name&gt; glazed-rain</code>
         <br>
         give info about current freezing rain (active|inactive).
      </li><br>
      <li><code>get &lt;name&gt; hail</code>
         <br>
         give info about current hail (active|inactive).
      </li><br>
      <li><code>get &lt;name&gt; heat</code>
         <br>
         give info about current heat (active|inactive).
      </li><br>
      <li><code>get &lt;name&gt; rain</code>
         <br>
         give info about current rain (active|inactive).
      </li><br>
      <li><code>get &lt;name&gt; snow</code>
         <br>
         give info about current snow (active|inactive).
      </li><br>
      <li><code>get &lt;name&gt; storm</code>
         <br>
         give info about current storm (active|inactive).
      </li><br>
      <li><code>get &lt;name&gt; forest-fire</code>
         <br>
         give info about current forest fire (active|inactive).
      </li><br>

   </ul>  
  
   <br>

   <a name="MoWaSset"></a>
   <b>Set</b>
   <ul>
      <br>
      <li><code>set &lt;name&gt; update</code>
         <br>
         Executes an imediate update of thunderstorm warnings.
      </li><br>
   </ul>  
  
   <br>
   <a name="MoWaSattr"></a>
   <b>Attributes</b>
   <ul>
      <br>
      <li><code>download</code>
         <br>
         Download maps during update (0|1). 
         <br>
      </li>
      <li><code>savepath</code>
         <br>
         Define where to store the map png files (default: /tmp/). 
         <br>
      </li>
      <li><code>maps</code>
         <br>
         Define the maps to download space seperated. For possible values see <code>MoWaSAsHtmlKarteLand</code>.
         <br>
      </li>
      <li><code>humanreadable</code>
         <br>
         Add additional Readings Warn_?_Start_Date, Warn_?_Start_Time, Warn_?_End_Date and Warn_?_End_Time containing the coresponding timetamp in a human readable manner. Additionally Warn_?_MoWaSLevel_Str and Warn_?_Type_Str will be added to device readings (0|1).
         <br>
      </li>
      <li><code>lang</code>
         <br>
         Overwrite requested language for short and long warn text. (de|en). 
         <br>
      </li>
      <li><code>sort_readings_by</code>
         <br>
         define how readings will be sortet (start|severity|creation).  
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

   <a name="MoWaSreading"></a>
   <b>Readings</b>
   <ul>
      <br>
      <li><b>Warn_</b><i>0|1|2|3...|9</i><b>_...</b> - active warnings</li>
      <li><b>WarnCount</b> - warnings count</li>
      <li><b>WarnMoWaSLevel</b> - total warn level </li>
      <li><b>WarnMoWaSLevel_Color</b> - total warn level color</li>
      <li><b>WarnMoWaSLevel_Str</b> - total warn level string</li>
      <li><b>Warn_</b><i>0</i><b>_AltitudeMin</b> - minimum altitude for warning </li>
      <li><b>Warn_</b><i>0</i><b>_AltitudeMax</b> - maximum altitude for warning </li>
      <li><b>Warn_</b><i>0</i><b>_EventID</b> - warning EventID </li>
      <li><b>Warn_</b><i>0</i><b>_Creation</b> - warning creation </li>
      <li><b>Warn_</b><i>0</i><b>_Creation_Date</b> - warning creation datum </li>
      <li><b>Warn_</b><i>0</i><b>_Creation_Time</b> - warning creation time </li>
      <li><b>currentIntervalMode</b> - default/warn, Interval is read from INTERVAL or INTERVALWARN Internal</li>
      <li><b>Warn_</b><i>0</i><b>_Start</b> - begin of warnperiod</li>
      <li><b>Warn_</b><i>0</i><b>_Start_Date</b> - start date of warnperiod</li>
      <li><b>Warn_</b><i>0</i><b>_Start_Time</b> - start time of warnperiod</li>
      <li><b>Warn_</b><i>0</i><b>_End</b> - end of warnperiod</li>
      <li><b>Warn_</b><i>0</i><b>_End_Date</b> - end date of warnperiod</li>
      <li><b>Warn_</b><i>0</i><b>_End_Time</b> - end time of warnperiod</li>
      <li><b>Warn_</b><i>0</i><b>_Severity</b> - Severity of thunderstorm (0 no thunderstorm, 4, 7, 11, .. heavy thunderstorm)</li>
      <li><b>Warn_</b><i>0</i><b>_Hail</b> - warning contains hail</li>
      <li><b>Warn_</b><i>0</i><b>_Type</b> - kind of thunderstorm</li>
      <li><b>Warn_</b><i>0</i><b>_Type_Str</b> - kind of thunderstorm (text)</li>
      <ul>
        <li><b>1</b> - unknown</li>
        <li><b>2</b> - storm</li>
        <li><b>3</b> - snow</li>
        <li><b>4</b> - rain</li>
        <li><b>5</b> - frost</li>
        <li><b>6</b> - forest fire</li>
        <li><b>7</b> - thunderstorm</li>
        <li><b>8</b> - glaze</li>
        <li><b>9</b> - heat</li>
        <li><b>10</b> - freezing rain</li>
        <li><b>11</b> - soil frost</li>
      </ul>
      <li><b>Warn_</b><i>0</i><b>_MoWaSLevel</b> - Severity of thunderstorm (0-5)</li>
      <li><b>Warn_</b><i>0</i><b>_MoWaSLevel_Str</b> - Severity of thunderstorm (text)</li>
      <li><b>Warn_</b><i>0</i><b>_levelName</b> - Level Warn Name</li>
      <li><b>Warn_</b><i>0</i><b>_ShortText</b> - short warn text</li>
      <li><b>Warn_</b><i>0</i><b>_LongText</b> - detailed warn text</li>
      <li><b>Warn_</b><i>0</i><b>_IconURL</b> - cumulated URL to display warn-icons from <a href="http://www.unwetterzentrale.de">www.unwetterzentrale.de</a></li>
   </ul>
   <br>

   <a name="MoWaSweblinks"></a>
   <b>Weblinks</b>
   <ul>
      <br>

      With the additional implemented functions <code>MoWaSAsHtml, MoWaSAsHtmlLite, MoWaSAsHtmlFP, MoWaSAsHtmlKarteLand and MoWaSAsHtmlMovie</code> HTML-Code will be created to display warnings and weathermovies, using weblinks.
      <br><br><br>
      Example:
      <br>
      <li><code>define UnwetterDetailiert weblink htmlCode {MoWaSAsHtml("MoWaS_device")}</code></li>
      <br>
      <li><code>define UnwetterLite weblink htmlCode {MoWaSAsHtmlLite("MoWaS_device")}</code></li>
      <br>
      <li><code>define UnwetterFloorplan weblink htmlCode {MoWaSAsHtmlFP("MoWaS_device")}</code></li>
      <br>
      <li><code>define UnwetterKarteLand weblink htmlCode {MoWaSAsHtmlKarteLand("MoWaS_device","Bayern")}</code></li>
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
      <li><code>define UnwetterKarteMovie weblink htmlCode {MoWaSAsHtmlMovie("MoWaS_device","currents")}</code></li>
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

<a name="MoWaS"></a>
<h3>MoWaS</h3> 
<ul>
   <a name="MoWaSdefine"></a>
   Das Modul extrahiert Bev�lkerungsschutzwarnungen(MoWaS) von <a href="http://www.unwetterzentrale.de">www.unwetterzentrale.de</a>.
   <br/>
   Hierfür wird die selbe Schnittstelle verwendet die auch die Android App <a href="http://www.alertspro.com">Alerts Pro</a> nutzt.
   Es werden maximal 10 Standortbezogene Unwetterwarnungen zur Verfügung gestellt.
   Weiterhin verfügt das Modul über HTML-Templates welche als weblink verwendet werden können.
   <br>
   <i>Es nutzt die Perl-Module JSON, Encode::Guess und HTML::Parse</i>.
   <br/><br/>
   <b>Define</b>
   <ul>
      <br>
      <code>define &lt;Name&gt; MoWaS [L&auml;ndercode] [Postleitzahl] [INTERVAL]</code>
      <br><br><br>
      Beispiel:
      <br>
      <code>define MoWaS_device MoWaS DE 86405 3600</code>
      <br>&nbsp;

      <li><code>[L&auml;ndercode]</code>
         <br>
         M&ouml;gliche Werte: DE ...<br/>
      </li><br>
      <li><code>[Postleitzahl/AreaID]</code>
         <br>
         Die Postleitzahl/AreaID des Ortes für den Unwetterinformationen abgefragt werden sollen. 
         <br>
      </li><br>
      <li><code>[INTERVAL]</code>
         <br>
         Definiert das Interval zur aktualisierung der Unwetterwarnungen. Das Interval wird in Sekunden angegeben, somit aktualisiert das Modul bei einem Interval von 3600 jede Stunde 1 mal. 
         <br>
      </li><br>
   </ul>
   <br>

   <a name="MoWaSget"></a>
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

     <a name="MoWaSset"></a>
   <b>Set</b>
   <ul>
      <br>
      <li><code>set &lt;name&gt; update</code>
         <br>
         Startet sofort ein neues Auslesen der Unwetterinformationen.
      </li><br>
   </ul>  
  
   <br>

   <a name="MoWaSattr"></a>
   <b>Attribute</b>
   <ul>
      <br>
      <li><code>download</code>
         <br>
         Download Unwetterkarten während des updates (0|1). 
         <br>
      </li>
      <li><code>savepath</code>
         <br>
         Pfad zum speichern der Karten (default: /tmp/). 
         <br>
      </li>
      <li><code>maps</code>
         <br>
         Leerzeichen separierte Liste der zu speichernden Karten. Für mögliche Karten siehe <code>MoWaSAsHtmlKarteLand</code>.
         <br>
      </li>
      <li><code>humanreadable</code>
         <br>
     Anzeige weiterer Readings Warn_?_Start_Date, Warn_?_Start_Time, Warn_?_End_Date, Warn_?_End_Time. Diese Readings enthalten aus dem Timestamp kalkulierte Datums/Zeit Angaben. Weiterhin werden folgende Readings aktivier: Warn_?_Type_Str und Warn_?_MoWaSLevel_Str welche den Unwettertyp als auch das Unwetter-Warn-Level als Text ausgeben. (0|1) 
         <br>
      </li>
      <li><code>lang</code>
         <br>
         Umschalten der angeforderten Sprache für kurz und lange warn text. (de|en|it|fr|es|..). 
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

   <a name="MoWaSreading"></a>
   <b>Readings</b>
   <ul>
      <br>
      <li><b>Warn_</b><i>0|1|2|3...|9</i><b>_...</b> - aktive Warnmeldungen</li>
      <li><b>WarnCount</b> - Anzahl der aktiven Warnmeldungen</li>
      <li><b>WarnMoWaSLevel</b> - Gesamt Warn Level </li>
      <li><b>WarnMoWaSLevel_Color</b> - Gesamt Warn Level Farbe</li>
      <li><b>WarnMoWaSLevel_Str</b> - Gesamt Warn Level Text</li>
      <li><b>Warn_</b><i>0</i><b>_AltitudeMin</b> - minimum Höhe für Warnung </li>
      <li><b>Warn_</b><i>0</i><b>_AltitudeMax</b> - maximum Höhe für Warnung </li>
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
        <li><b>8</b> - Glätte</li>
        <li><b>9</b> - Hitze</li>
        <li><b>10</b> - Glatteisregen</li>
        <li><b>11</b> - Bodenfrost</li>
      </ul>
      <li><b>Warn_</b><i>0</i><b>_MoWaSLevel</b> - Unwetterwarnstufe (0-5)</li>
      <li><b>Warn_</b><i>0</i><b>_MoWaSLevel_Str</b> - Unwetterwarnstufe (text)</li>
      <li><b>Warn_</b><i>0</i><b>_levelName</b> - Level Warn Name</li>
      <li><b>Warn_</b><i>0</i><b>_ShortText</b> - Kurzbeschreibung der Warnung</li>
      <li><b>Warn_</b><i>0</i><b>_LongText</b> - Ausführliche Unwetterbeschreibung</li>
      <li><b>Warn_</b><i>0</i><b>_IconURL</b> - Kumulierte URL um Warnungs-Icon von <a href="http://www.unwetterzentrale.de">www.unwetterzentrale.de</a> anzuzeigen</li>
   </ul>
   <br>

   <a name="MoWaSweblinks"></a>
   <b>Weblinks</b>
   <ul>
      <br>

      &Uuml;ber die Funktionen <code>MoWaSAsHtml, MoWaSAsHtmlLite, MoWaSAsHtmlFP, MoWaSAsHtmlKarteLand, MoWaSAsHtmlMovie</code> wird HTML-Code zur Warnanzeige und Wetterfilme über weblinks erzeugt.
      <br><br><br>
      Beispiele:
      <br>
      <li><code>define UnwetterDetailiert weblink htmlCode {MoWaSAsHtml("MoWaS_device")}</code></li>
      <br>
      <li><code>define UnwetterLite weblink htmlCode {MoWaSAsHtmlLite("MoWaS_device")}</code></li>
      <br>
      <li><code>define UnwetterFloorplan weblink htmlCode {MoWaSAsHtmlFP("MoWaS_device")}</code></li>
      <br>
      <li><code>define UnwetterKarteLand weblink htmlCode {MoWaSAsHtmlKarteLand("MoWaS_device","Bayern")}</code></li>
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
      <li><code>define UnwetterKarteMovie weblink htmlCode {MoWaSAsHtmlMovie("MoWaS_device","niederschlag-wolken-de")}</code></li>
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
