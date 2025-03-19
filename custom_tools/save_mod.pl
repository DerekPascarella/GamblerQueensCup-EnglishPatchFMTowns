#!/usr/bin/perl
#
# save_mod.pl
# Save file modification utility for the FM Towns game "Gambler - Queen's Cup".
#
# Written by Derek Pascarella (ateam)

# Include necessary modules.
use Encode;
use strict;

# Initialize input variables.
my $save_file = $ARGV[0];

# Set header used in CLI messages.
my $cli_header = "\nGambler: Queen's Cup\nSave File Modifier\n\nWritten by Derek Pascarella (ateam)\n\nNote that this program makes direct changes to the\nsupplied floppy disk image!\n\n";

# Define offsets for all six possible save files and their metadata.
my %save_map = (
					1 => {
							'Money' => 12211,
							'Date' => 12234
						 },
					2 => {
							'Money' => 12310,
							'Date' => 12333
						 },
					3 => {
							'Money' => 12409,
							'Date' => 12432
						 },
					4 => {
							'Money' => 12508,
							'Date' => 12531
						 },
					5 => {
							'Money' => 12607,
							'Date' => 12630
						 },
					6 => {
							'Money' => 12706,
							'Date' => 12729
						 }
				);

# No input file specified.
if($save_file eq "")
{
	print $cli_header;
	print STDERR "Error: No save file specified.\n";
	print STDERR "       Please drag a .D88 format disk image onto this program.\n\n";
	print "Press Enter to exit.\n";
	<STDIN>;

	exit;
}
# Input file is the wrong format
elsif($save_file !~ /\.D88$/i || !valid_save_file($save_file))
{
	print $cli_header;
	print STDERR "Error: Invalid save file specified..\n";
	print STDERR "       Please drag a .D88 format disk image onto this program.\n\n";
	print "Press Enter to exit.\n";
	<STDIN>;

	exit;
}
# Error with input file.
elsif(!-e $save_file || !-R $save_file)
{
	print $cli_header;
	print STDERR "Error: Specified save file does not exist or is unreadable.\n\n";
	print "Press Enter to exit.\n";
	<STDIN>;

	exit;
}

# Default main loop exit to false.
my $exit = 0;

# Default user-selected option to zeor.
my $option = 0;

# Default save number to zero.
my $save_number = 0;

# Display menu until user exits.
while(!$exit)
{
	# Clear the screen.
	system($^O eq 'MSWin32' ? 'cls' : 'clear');

	# Parse number of save files.
	my $save_count_bytes = read_bytes_at_offset($save_file, 6, 12144);
	my @save_count_byte_array = $save_count_bytes =~ /../g;
	my $save_count = grep { /^FF$/i } @save_count_byte_array;

	# Status message.
	print $cli_header;

	# Default menu.
	if($option == 0)
	{
		# Status message.
		print $save_count . " save file(s) found on disk:\n";

		# Iterate through each save file.
		for(1 .. $save_count)
		{
			# Store offsets for money and date.
			my $money_offset = $save_map{$_}->{'Money'};
			my $date_offset = $save_map{$_}->{'Date'};

			# Store money and date.
			my $money = hex(endian_swap(read_bytes_at_offset($save_file, 3, $money_offset)));
			my $date = pack('H*', read_bytes_at_offset($save_file, 17, $date_offset));
			$date =~ s/^(.{8})/$1 (/;

			# Display money and date.
			print $_ . ") " . $date . ") - " . $money . " yen\n";
		}

		# Display options.
		print "\nEnter an option number:\n";
		print "1 - Modify money\n";
		print "2 - Exit\n";

		while($option != 1 && $option != 2)
		{
			print "> ";
			chop($option = <STDIN>);
			$option =~ s/\D//g;
		}

		# Prompt for save file number to modify.
		if($option == 1)
		{
			print "\nEnter save file number:\n";

			while($save_number < 1 || $save_number > $save_count)
			{
				print "> ";
				chop($save_number = <STDIN>);
				$save_number =~ s/\D//g;
			}
		}
	}
	# Modify money.
	elsif($option == 1)
	{
		# Store offsets for money and date.
		my $money_offset = $save_map{$save_number}->{'Money'};
		my $date_offset = $save_map{$save_number}->{'Date'};

		# Store money and date.
		my $money = hex(endian_swap(read_bytes_at_offset($save_file, 3, $money_offset)));
		my $date = pack('H*', read_bytes_at_offset($save_file, 17, $date_offset));
		$date =~ s/^(.{8})/$1 (/;

		# Display money and date.
		print "Modifying money for the following save file:\n";
		print $save_number . ") " . $date . ") - " . $money . " yen\n";

		# Display prompt.
		print "\nEnter new amount (9999999 yen maximum, 0 yen minimum):\n";
		
		my $new_amount = -1;

		while($new_amount < 0 || $new_amount > 9999999)
		{
			print "> ";
			chop($new_amount = <STDIN>);
		}

		# Convert money amount to little-endian hex representation.
		$new_amount = endian_swap(decimal_to_hex($new_amount, 6));

		# Patch money amount.
		patch_bytes($save_file, $new_amount, $money_offset);

		# Status message.
		print "\nSave file updated!\n\n";
		print "Press Enter to return to main menu.\n";
		<STDIN>;

		# Revert to default option zero.
		$option = 0;
	}

	# Exit.
	if($option == 2)
	{
		$exit = 1;
	}
}

# Subroutine to validate a floppy disk image as D88 format.
sub valid_save_file
{
	my $file = $_[0];
	
	my $signature = read_bytes_at_offset($file, 5, 0);

	if($signature ne "4878434645")
	{
		return 0;
	}

	my $check_byte = read_bytes_at_offset($file, 1, 12144);

	if($check_byte ne "ff")
	{
		return 0;
	}

	return 1;
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