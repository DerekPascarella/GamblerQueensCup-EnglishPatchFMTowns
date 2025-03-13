#!/usr/bin/perl
#
# lib_idx_extract.pl
# LIB/IDX archive extractor for the FM Towns game "Gambler - Queen's Cup".
#
# Written by Derek Pascarella (ateam)

# Include necessary modules.
use strict;

# Set input/output paths.
my $input_folder = "../extracted_original/";
my $output_folder = "./lib_idx_extracted/";

# Store file list of input directory in array.
opendir(DIR, $input_folder);
my @input_files = grep !/^\.\.?$/, readdir(DIR);
@input_files = sort { no warnings; $a <=> $b || $a cmp $b } @input_files;
@input_files = grep /(?:REX|DIC|SDX)\.IDX/, @input_files;
closedir(DIR);

# Status message.
print "\nFound " . scalar(@input_files) . " LIB/IDX file(s) in input folder.\n";

# Iterate through each input file.
for(my $i = 0; $i < scalar(@input_files); $i ++)
{
	# Store total file count from archive.
	my $file_count = hex(&endian_swap(&read_bytes_at_offset($input_folder . "/" . $input_files[$i], 2, 4)));

	# Status message.
	print "\nProcessing " . $input_files[$i] . " (" . $file_count . " files)...\n";

	# Store base name without file extension.
	(my $input_file_basename = $input_files[$i]) =~ s/\.[^.]+$//;

	# Store name of data file.
	my $data_file_name = $input_file_basename . ".LIB";

	# Initialize extracted file count to zero.
	my $extracted_file_count = 0;

	# Initialize header seek position to eight.
	my $header_seek_position = 8;

	# Initialize end-of-header to zero.
	my $end_of_header = 0;

	# Seek through archive header until it ends.
	while($extracted_file_count < $file_count)
	{
		# Store hex representation of filename.
		my $file_name_hex = &read_bytes_at_offset($input_folder . "/" . $input_files[$i], 16, $header_seek_position);

		# Store filename.
		my $file_name_string = pack "H*", $file_name_hex;
		$file_name_string =~ s/\P{IsPrint}//g;
		$file_name_string =~ s/[^[:ascii:]]+//g;
		
		# Store file offset.
		my $file_offset_hex_le = &read_bytes_at_offset($input_folder . "/" . $input_files[$i], 4, $header_seek_position + 20);
		my $file_offset_hex_be = &endian_swap($file_offset_hex_le);
		my $file_offset_dec = hex($file_offset_hex_be);

		# Store file length.
		my $file_size_hex_le = &read_bytes_at_offset($input_folder . "/" . $input_files[$i], 4, $header_seek_position + 16);
		my $file_size_hex_be = &endian_swap($file_size_hex_le);
		my $file_size_dec = hex($file_size_hex_be);

		# Status message.
		print "  -> " . $file_name_string . " - Offset " . $file_offset_dec . " (0x" . $file_offset_hex_be . ") - Size " . $file_size_dec . " bytes\n";

		# Store file conents.
		my $file_hex = &read_bytes_at_offset($input_folder . "/" . $data_file_name, $file_size_dec, $file_offset_dec);

		# Create output folder corresponding to source archive.
		mkdir($output_folder . "/" . $input_file_basename);

		# Write file.
		&write_bytes($output_folder . "/" . $input_file_basename . "/" . $file_name_string, $file_hex);

		# Increase header seek position by 24 bytes.
		$header_seek_position += 24;

		# Increase extracted file count by one.
		$extracted_file_count ++;
	}
}

# Status message.
print "\nComplete!\n\n";

# Subroutine to return hexadecimal representation of a decimal number.
#
# 1st parameter - Decimal number.
# 2nd parameter - Number of bytes with which to represent hexadecimal number (omit parameter for no
#                 padding).
sub decimal_to_hex
{
	if($_[1] eq "")
	{
		$_[1] = 0;
	}

	return sprintf("%0" . $_[1] * 2 . "X", $_[0]);
}

# Subroutine to swap between big/little endian by reversing order of bytes from specified hexadecimal
# data.
#
# 1st parameter - Hexadecimal representation of data.
sub endian_swap
{
	(my $hex_data = $_[0]) =~ s/\s+//g;
	my @hex_data_array = ($hex_data =~ m/../g);

	return join("", reverse(@hex_data_array));
}

# Subroutine to read a specified number of bytes, starting at a specific offset (in decimal format), of
# a specified file, returning hexadecimal representation of data.
#
# 1st parameter - Full path of file to read.
# 2nd parameter - Number of bytes to read.
# 3rd parameter - Offset at which to read.
sub read_bytes_at_offset
{
	my $input_file = $_[0];
	my $byte_count = $_[1];
	my $read_offset = $_[2];

	if((stat $input_file)[7] < $read_offset + $byte_count)
	{
		die "Offset for read_bytes_at_offset is outside of valid range.\n";
	}

	open my $filehandle, '<:raw', $input_file or die $!;
	seek $filehandle, $read_offset, 0;
	read $filehandle, my $bytes, $byte_count;
	close $filehandle;
	
	return unpack 'H*', $bytes;
}

# Subroutine to write a sequence of hexadecimal values to a specified file.
#
# 1st parameter - Full path of file to write.
# 2nd parameter - Hexadecimal representation of data to be written to file.
sub write_bytes
{
	my $output_file = $_[0];
	(my $hex_data = $_[1]) =~ s/\s+//g;
	my @hex_data_array = split(//, $hex_data);

	open my $filehandle, '>:raw', $output_file or die $!;
	binmode $filehandle;

	for(my $i = 0; $i < scalar(@hex_data_array); $i += 2)
	{
		my($high, $low) = @hex_data_array[$i, $i + 1];
		print $filehandle pack "H*", $high . $low;
	}

	close $filehandle;
}