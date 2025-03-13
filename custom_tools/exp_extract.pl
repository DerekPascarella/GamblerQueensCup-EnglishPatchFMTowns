#!/usr/bin/perl
#
# exp_extract.pl
# Extract Shift-JIS text from the FM Towns game "Gambler - Queen's Cup" using
# TextScan (https://www.romhacking.net/utilities/1164/).
#
# Written by Derek Pascarella (ateam)

# Include necessary modules.
use strict;

# Define paths.
my $input_file = "..\\extracted_new\\GAMBLER.EXP";
my $text_dump_output_folder = ".\\exp_extracted\\";
my $textscan_location = "TextScan.exe";
my $shift_jis_table = "sjis.tbl";

# Invoke TextScan.exe to perform text dump.
system "$textscan_location \"$input_file\" $shift_jis_table -l 2 -e shift_jis -o \"$text_dump_output_folder\\GAMBLER.EXP\.TXT\"";