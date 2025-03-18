#!/usr/bin/perl
#
# lib_idx_rebuild.pl
# LIB/IDX rebuilder for the FM Towns game "Gambler - Queen's Cup".
#
# Written by Derek Pascarella (ateam)

# Include necessary modules.
use utf8;
use strict;
use HTML::Entities;
use Encode 'encode';
use Spreadsheet::ParseXLSX;
use String::HexConvert ':all';
use Spreadsheet::Read qw(ReadData);

# Set STDOUT encoding to UTF-8.
binmode(STDOUT, "encoding(UTF-8)");

# Set dialogue box width to 60 characters for text wrapping, as well as define
# maximum numbers of lines per box.
my $max_chars_per_line = 60;
my $max_line_count = 5;

# Remove previous warning log file.
unlink("warning.log");

# Declare input arguments.
my $mode = $ARGV[0];

# Set input/output paths.
my $spreadsheet_folder = "./xlsx_new/";
my $extracted_original_folder = "./lib_idx_extracted/";
my $output_folder = "./lib_idx_rebuilt/";
my $game_data_folder_original = "../extracted_original/";
my $game_data_folder_new = "../extracted_new/";

# Store folder list of input directory in array.
opendir(DIR, $spreadsheet_folder);
my @spreadsheet_folder = grep !/^\.\.?$/, readdir(DIR);
closedir(DIR);

# Iterate through each spreadsheet folder.
foreach(@spreadsheet_folder)
{
	# Store first six bytes of original LIB archive in rolling hex representation, which will
	# be written to disk as newly generated archive.
	my $lib_hex = &read_bytes($game_data_folder_original . "/" . $_ . ".LIB", 6);

	# Store first eight bytes of original IDX file in rolling hex representation, which will
	# be written to disk as newly generated index.
	my $idx_hex = &read_bytes($game_data_folder_original . "/" . $_ . ".IDX", 8);

	# Store array of originally extracted files from archive.
	opendir(DIR, $extracted_original_folder . "/" . $_);
	my @original_files = grep !/^\.\.?$/, readdir(DIR);
	@original_files = sort { no warnings; $a <=> $b || $a cmp $b } @original_files;
	closedir(DIR);

	# Status message.
	print "\nFound " . scalar(@original_files) . " original file(s) for archive " . $_ . ".\n\n";

	# Initialize rolling offset for indivdual LIB archive files to six bytes.
	my $idx_offset = 6;

	# Iterate through each originally extracted archive file and use them to rebuild LIB unless
	# translated spreadsheet exists.
	for(my $i = 0; $i < scalar(@original_files); $i ++)
	{
		# Generate hex representation of file name for IDX.
		my $idx_file_name = ascii_to_hex($original_files[$i]);

		# Initialize file size (in bytes) to zero for individual archive files, used later for IDX.
		my $idx_file_size = 0;

		# Pad file name byte array to 16 bytes.
		for((length($idx_file_name) / 2) + 1 .. 16)
		{
			$idx_file_name .= "00";
		}

		# Append file name to rolling hex representation of IDX.
		$idx_hex .= $idx_file_name;

		# Translated spreadsheet doesn't exist, use original.
		if(!-e $spreadsheet_folder . "/" . $_ . "/" . $original_files[$i] . ".xlsx")
		{
			# Status message.
			print "-> Using original file " . $original_files[$i] . ".\n";

			# Add original archive file to rolling LIB hex representation.
			$lib_hex .= &read_bytes($extracted_original_folder . "/" . $_ . "/" . $original_files[$i]);

			# Store file size.
			$idx_file_size = (stat $extracted_original_folder . "/" . $_ . "/" . $original_files[$i])[7];
		}
		# Otherwise, process spreadsheet.
		else
		{
			# Declare translation hex representation, which will be used to populate "lib_hex".
			my $translation_hex;

			# Read and store spreadsheet.
			my $spreadsheet = ReadData($spreadsheet_folder . "/" . $_ . "/" . $original_files[$i] . ".xlsx");
			my @spreadsheet_rows = Spreadsheet::Read::rows($spreadsheet->[1]);

			# Status message.
			print "-> Processing new " . $original_files[$i] . ".xlsx (" . (scalar(@spreadsheet_rows) - 1) . " rows).\n";

			# Iterate through each row of spreadsheet.
			for(my $j = 1; $j < scalar(@spreadsheet_rows); $j ++)
			{
				# Store data from current spreadsheet row.
				my $type = $spreadsheet_rows[$j][0];
				my $value = $spreadsheet_rows[$j][1];
				my $speaker = $spreadsheet_rows[$j][2];
				my $translation = decode_entities($spreadsheet_rows[$j][3]);
				my $notes = $spreadsheet_rows[$j][4];
				my $orig_hex = unpack('H*', encode('Shift_JIS', $value));
				$orig_hex =~ s/3F//gi;

				# Quick fix for "Juri".
				$translation =~ s/Juri/Judy/g;

				# Verbose status message.
				if($mode eq "verbose")
				{
					print "    Type: " . $type . "\n";
					print "    Value: " . $value . " (hex: " . $orig_hex . " - length: " . length($orig_hex) . ")\n";
					print "    Speaker: " . $speaker . "\n";
				
					if($type eq "String")
					{
						print "    Translation: " . $translation . "\n\n";
					}
				}

				# Process control codes in between text chunks.
				if($type eq "Control Code")
				{				
					# Add control code to rolling hex representation of LIB.
					$lib_hex .= $value;

					# Add control code's length to byte length for entire file.
					$idx_file_size += length($value) / 2;
				}
				# Process text strings.
				elsif($type eq "String")
				{
					# Adjust maximum lines and characters per line for quiz scenes.
					if($original_files[$i] =~ /REX/ && $notes !~ /FORCE60/)
					{
						$max_chars_per_line = 66;
						$max_line_count = 3;
					}
					else
					{
						$max_chars_per_line = 60;
						$max_line_count = 5;
					}

					# No speaker name/type specified.
					if($speaker eq "" && $translation ne "")
					{
						# Status message.
						print "    WARNING: No speaker name/type specified (row " . ($j + 1) . ")!\n\n";

						# Write details to warning log.
						open(my $warning_file, '>>', "warning.log");
						print $warning_file $original_files[$i] . ".xlsx - Row " . ($j + 1) . " is missing speaker name/type.\n";
						close $warning_file;
					}

					#
					# NOTE:
					# Color palette changes from scene to scene, so this feature was disabled.
					#
					# # Construct speaker label with custom text color.
					# if($speaker !~ /Special/ && $speaker ne "Narrator" && $speaker ne "N/A")
					# {
					# 	if($speaker eq "Takagi" || $speaker eq "Takagi (internal)")
					# 	{
					# 		$speaker = "*e[[ TAKAGI ]]*f";
					# 	}
					# 	elsif($speaker eq "Aya")
					# 	{
					# 		$speaker = "*p[[ AYA ]]*f";
					# 	}
					# 	elsif($speaker eq "Judy" || $speaker eq "Juri")
					# 	{
					# 		$speaker = "*c[[ JUDY ]]*f";
					# 	}
					# 	elsif($speaker eq "Rena")
					# 	{
					# 		$speaker = "*q[[ RENA ]]*f";
					# 	}
					# 	elsif($speaker eq "Boss")
					# 	{
					# 		$speaker = "*o[[ BOSS ]]*f";
					# 	}

					# 	# Prepend speaker tag to translated text.
					# 	$translation = $speaker . " " . $translation;
					# }

					# Add speaker labels to non-empty translations.
					if($translation ne "")
					{
						# Add speaker label for Takagi, and enclose text in parenthesis.
						if($speaker eq "Takagi (internal)")
						{
							# Remove parenthesis if they already exist.
							$translation =~ s/\(//g;
							$translation =~ s/\)//g;

							$translation = "[[ TAKAGI ]] (" . $translation . ")";
						}
						# Add standard speaker label.
						elsif($speaker !~ /Special/ && $speaker ne "Narrator" && $speaker ne "N/A")
						{
							# Quick fix for "Juri".
							$speaker =~ s/Juri/Judy/g;

							$translation = "[[ " . uc($speaker) . " ]] " . $translation;
						}
					}				

					# Use placeholder for empty translations.
					if($translation eq "")
					{
						# Store hex representation of English text.
						$translation_hex = ascii_to_hex("Row " . ($j + 1));
					}
					# Perform text wrap unless specially marked (e.g., intro text).
					elsif($speaker !~ /Special/ && $speaker ne "N/A")
					{
						# Clean translated text.
						$translation =~ s/^\s+|\s+$//g;
						$translation =~ s/ +/ /;
						$translation =~ s/\s+/ /g;
						$translation =~ s/’/'/g;
						$translation =~ s/”/"/g;
						$translation =~ s/“/"/g;
						$translation =~ s/\.{4,}/\.\.\./g;
						$translation =~ s/…/\.\.\./g;
						$translation =~ s/\P{IsPrint}//g;
						$translation =~ s/[^[:ascii:]]+//g;

						# Replace carrots (^) with empty spaces.
						$translation =~ s/\^/ /g;

						# Break text up by word, building each line to fill maximum horizontal space.
						my @translation_words = split(/\s+/, $translation);
						my @translation_wrapped;
						my $line = "";
						my $line_length = 0;

						foreach my $word (@translation_words)
						{
							my $word_length = length($word);

							# If the word contains an asterisk, subtract four from its length (e.g.,
							# *fhighlighted*a).
							if($word =~ /^\*.*\*$/)
							{
								$word_length -= 4;
							}
							elsif($word =~ /\*/)
							{
								$word_length -= 2;
							}

							# Start a new line if adding this word exceeds the maximum line length.
							if($line_length + $word_length + ($line_length > 0 ? 1 : 0) > $max_chars_per_line)
							{
								# Append "*r" if the line is shorter than maximum length, ensuring
								# no leading space.
								if($line_length < $max_chars_per_line)
								{
									$line .= "*r";
								}

								push(@translation_wrapped, $line);
								
								$line = $word;
								
								$line_length = $word_length;
							}
							# Otherwise, append the word to the current line.
							else
							{
								# Append space only if this isn't the first word in the line
								if($line_length > 0)
								{
									$line .= " ";
								}

								$line .= $word;

								$line_length += $word_length + ($line_length > 0 ? 1 : 0);
							}
						}

						# Push the final line if it's not empty.
						if($line ne "")
						{
							push(@translation_wrapped, $line);
						}

						# Throw warning if English text exceeds maximum line count.
						if(scalar(@translation_wrapped) > $max_line_count)
						{
							# Status message.
							print "    WARNING: English text exceeds " . $max_line_count . " lines (row " . ($j + 1) . ")!\n\n";

							# Write details to warning log.
							open(my $warning_file, '>>', "warning.log");
							print $warning_file $original_files[$i] . ".xlsx - Row " . ($j + 1) . " exceeds " . $max_line_count . " lines.\n";
							close $warning_file;
						}

						# Store hex representation of English text.
						$translation_hex = ascii_to_hex(join("", @translation_wrapped));

						# Replace speaker label brackets with Shift-JIS ([[ becomes 【 and ]]
						# becomes 】).
						$translation_hex =~ s/5B5B/8179/gi;
						$translation_hex =~ s/5D5D/817A/gi;

						# Remove erroneous leading data from hex representation of English
						# text.
						$translation_hex =~ s/^ff//i;

						# Verbose status message.
						if($mode eq "verbose")
						{
							print "    Translation Hex: " . $translation_hex . "\n\n";
							print "    Translation Folded:\n" . join("", @translation_wrapped) . "\n\n";
						}
					}
					# Directly process with no text manipulation.
					else
					{
						# Insert old menu text by using direct hex data.
						if($speaker eq "Special2")
						{
							# Clean translated text.
							$translation =~ s/^\s+|\s+$//g;
							
							$translation_hex = $translation;
						}
						# Otherwise, process other non-standard dialogue text.
						else
						{
							# Clean translated text.
							$translation =~ s/^\s+|\s+$//g;
							$translation =~ s/ +/ /;
							$translation =~ s/\s+/ /g;
							$translation =~ s/’/'/g;
							$translation =~ s/”/"/g;
							$translation =~ s/“/"/g;
							$translation =~ s/\.{4,}/\.\.\./g;
							$translation =~ s/…/\.\.\./g;
							$translation =~ s/\P{IsPrint}//g;
							$translation =~ s/[^[:ascii:]]+//g;

							# Replace carrots (^) with empty spaces.
							$translation =~ s/\^/ /g;

							# Store hex representation of English text.
							$translation_hex = ascii_to_hex($translation);

							# Remove erroneous leading data from hex representation of English
							# text.
							$translation_hex =~ s/^ff//i;

							# Verbose status message.
							if($mode eq "verbose")
							{
								print "    Translation Hex: " . $translation_hex . "\n\n";
							}
						}
					}

					# Store length (in bytes) of translated text chunk, used for new offset
					# calculations.
					my $translation_byte_length = length($translation_hex) / 2;

					# Replace string chunk length from previous control code to reflect new
					# length (i.e., replace last two bytes of LIB's rolling hex representation).
					if($spreadsheet_rows[$j-1][0] eq "Control Code" && $speaker ne "Special2")
					{
						substr($lib_hex, -4, 4) = &endian_swap(&decimal_to_hex($translation_byte_length, 2));
					}

					# Append string chunk's hex representation.
					$lib_hex .= $translation_hex;

					# Add translated text's length to byte length for entire file.
					$idx_file_size += $translation_byte_length;
				}
			}
		}

		# Append file size to rolling IDX.
		$idx_hex .= &endian_swap(&decimal_to_hex($idx_file_size, 4));

		# Append file offset to rolling IDX.
		$idx_hex .= &endian_swap(&decimal_to_hex($idx_offset, 4));

		# Add file size to rolling IDX offset.
		$idx_offset += $idx_file_size;
	}

	# Write new LIB file.
	&write_bytes($output_folder . "/" . $_ . ".LIB", $lib_hex);
	&write_bytes($game_data_folder_new . "/" . $_ . ".LIB", $lib_hex);

	# Write new IDX file.
	&write_bytes($output_folder . "/" . $_ . ".IDX", $idx_hex);
	&write_bytes($game_data_folder_new . "/" . $_ . ".IDX", $idx_hex);

	# Extra new line for spacing.
	print "\n";
}

# Status message.
print "Rebuild complete!\n";

# If running via bundled executable on Windows, display prompt to close window.
if($^O eq 'MSWin32')
{
	print "\nPress Enter to close this window...\n";
	<STDIN>;
}

# Subroutine to read a specified number of bytes (starting at the beginning) of a specified file,
# returning hexadecimal representation of data.
#
# 1st parameter - Full path of file to read.
# 2nd parameter - Number of bytes to read (omit parameter to read entire file).
sub read_bytes
{
	my $input_file = $_[0];
	my $byte_count = $_[1];

	if($byte_count eq "")
	{
		$byte_count = (stat $input_file)[7];
	}

	open my $filehandle, '<:raw', $input_file or die $!;
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