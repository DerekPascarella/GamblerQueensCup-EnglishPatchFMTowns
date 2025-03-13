#!/usr/bin/perl

use utf8;
use ShiftJIS::String;
use String::HexConvert ':all';
use Encode qw(decode encode);

# Create empty "script_entries" array.
my @script_entries = ();

# Open script file for processing.
open(FH, '<', "exp_extracted/DERBY.DBX.TXT") or die $!;
while(<FH>)
{
	# Remove carriage returns.
	$_ =~ s/\r\n//g;

	# Copy original script entry for Shift-JIS length calculation later on.
	my $text_original = $_;

	# Encode script entry from Shift-JIS to UTF-8.
	$_ = Encode::encode("utf-8", Encode::decode("shiftjis", $_));

	# Skip empty lines.
	next if /^\s*$/;

	# Store script entry's offset in a new element of "script_entries" array.
	if($_ =~ /^Position:/)
	{
		$_ =~ s/Position: //g;
		push(@script_entries, hex($_));
	}
	# Append script entry itself to last element of "script_entries" array, along with its length in bytes.
	else
	{
		$script_entries[scalar(@script_entries) - 1] .= "|" . $_ . "|" . (ShiftJIS::String::length($text_original) * 2);
	}
}
close(FH);

my @horse_names = ();

open(FH, '<', "horse_names.txt") or die $!;
while(<FH>)
{
	next if /^\s*$/;
	chomp;
	$_ =~ s/\r\n//g;
	push(@horse_names, $_)
}

for(my $i = 0; $i < scalar(@script_entries); $i ++)
{
	#print $script_entries[$i] . "\n";
	my @split = split(/\|/, $script_entries[$i]);
	my $pos = $split[0];
	my $len = $split[2];

	print "[$i] Pos $pos Len $len\n";

	my $name = $horse_names[$i];

	for(length($name) .. $len - 1)
	{
		$name .= " ";
	}

	print "    name [$name]\n";

	my $hex = ascii_to_hex($name);

	print $hex . "\n\n";

	&patch_bytes("../extracted_new/DERBY.DBX", $hex, $pos);
}

for(my $i = 0; $i < scalar(@horse_names); $i ++)
{
	#print $horse_names[$i] . "\n";
}




# Subroutine to write a sequence of hexadecimal values at a specified offset (in decimal format) into
# a specified file, as to patch the existing data at that offset.
#
# 1st parameter - Full path of file in which to insert patch data.
# 2nd parameter - Hexadecimal representation of data to be inserted.
# 3rd parameter - Offset at which to patch.
sub patch_bytes
{
	my $output_file = $_[0];
	(my $hex_data = $_[1]) =~ s/\s+//g;
	my @hex_data_array = split(//, $hex_data);
	my $patch_offset = $_[2];

	if((stat $output_file)[7] < $patch_offset + (scalar(@hex_data_array) / 2))
	{
		die "Offset for patch_bytes is outside of valid range.\n";
	}

	open my $filehandle, '+<:raw', $output_file or die $!;
	binmode $filehandle;
	seek $filehandle, $patch_offset, 0;

	for(my $i = 0; $i < scalar(@hex_data_array); $i += 2)
	{
		my($high, $low) = @hex_data_array[$i, $i + 1];
		print $filehandle pack "H*", $high . $low;
	}

	close $filehandle;
}