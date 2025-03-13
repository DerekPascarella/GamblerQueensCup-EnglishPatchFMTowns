#!/usr/bin/perl
#
# lib_text_extract.pl
# LIB text extractor for the FM Towns game "Gambler - Queen's Cup".
#
# Written by Derek Pascarella (ateam)

# Include necessary modules.
use utf8;
use JSON;
use strict;
use HTTP::Tiny;
use Spreadsheet::WriteExcel;
use Encode qw(decode encode);
use URI::Encode qw(uri_encode uri_decode);

# Set STDOUT encoding to UTF-8.
binmode(STDOUT, "encoding(UTF-8)");

# Set input/output paths.
my $input_folder = "./lib_idx_extracted/";
my $output_folder = "./xls/";

# Store valid ASCII, Shift-JIS, and half-width Shift-JIS characters into hashes.
my %valid_ascii = &generate_character_map_hash("ascii.txt");
my %valid_shiftjis = &generate_character_map_hash("shift-jis.txt");
my %valid_shiftjis_half = &generate_character_map_hash("shift-jis-half.txt");

# Store folder list of input directory in array.
opendir(DIR, $input_folder);
my @folders = grep !/^\.\.?$/, readdir(DIR);
closedir(DIR);

# Iterate through each folder.
foreach(@folders)
{
	# Store archive file name.
	my $archive_name = $_ . ".LIB";

	# Store file list of directory in array.
	opendir(DIR, $input_folder . "/" . $_);
	my @files = grep !/^\.\.?$/, readdir(DIR);
	closedir(DIR);

	# Iterate through each extracted archive file.
	for(my $i = 0; $i < scalar(@files); $i ++)
	{
		# Status message.
		print "\n[Processing " . $archive_name . " -> " . $files[$i] . "]\n";

		# Store each byte of file into element of array.
		my @file_bytes = (&read_bytes($input_folder . "/" . $_ . "/" . $files[$i]) =~ m/../g);

		# Initialize string chunk count to one.
		my $string_chunk_count = 0;

		# Declare string chunk hash.
		my %string_chunks;

		# Declare chunk type flag.
		my $type_flag;

		# Iterate through byte array, processing each.
		for(my $j = 0; $j < scalar(@file_bytes); $j ++)
		{
			# Current and next byte are part of Shift-JIS pair.
			if(exists $valid_shiftjis{uc($file_bytes[$j] . $file_bytes[$j+1])})
			{
				# If beginning of byte array, set type and flag to string.
				if($j == 0)
				{
					$type_flag = "string";
					$string_chunks{$string_chunk_count}{'Type'} = 'String';
				}
				# If flag is set to control code, change to string and increase chunk count by one.
				elsif($type_flag eq "control_code")
				{
					$type_flag = "string";
					$string_chunk_count ++;
					$string_chunks{$string_chunk_count}{'Type'} = 'String';
				}

				# Append byte pair to current hash key's value.
				$string_chunks{$string_chunk_count}{'Value'} .= $file_bytes[$j] . $file_bytes[$j+1];

				# Skip ahead one extra byte.
				$j ++;
			}
			# Current and next byte are part of custom-mapped Shift-JIS pair.
			elsif(($file_bytes[$j] eq "85" && hex($file_bytes[$j+1]) >= 79 && hex($file_bytes[$j+1]) <= 241) ||
				  ($file_bytes[$j] eq "86" && hex($file_bytes[$j+1]) >= 79 && hex($file_bytes[$j+1]) <= 241) ||
				  ($file_bytes[$j] eq "87" && hex($file_bytes[$j+1]) >= 64 && hex($file_bytes[$j+1]) <= 150))
			{
				# If beginning of byte array, set type and flag to string.
				if($j == 0)
				{
					$type_flag = "string";
					$string_chunks{$string_chunk_count}{'Type'} = 'String';
				}
				# If flag is set to control code, change to string and increase chunk count by one.
				elsif($type_flag eq "control_code")
				{
					$type_flag = "string";
					$string_chunk_count ++;
					$string_chunks{$string_chunk_count}{'Type'} = 'String';
				}

				# Translate custom Shift-JIS byte-pair to standard format.
				if($file_bytes[$j] eq "85")
				{
					$file_bytes[$j] = "82";
				}
				elsif($file_bytes[$j] eq "86")
				{
					$file_bytes[$j] = "82";
				}
				elsif($file_bytes[$j] eq "87")
				{
					$file_bytes[$j] = "83";
				}

				# Append byte pair to current hash key's value.
				$string_chunks{$string_chunk_count}{'Value'} .= $file_bytes[$j] . $file_bytes[$j+1];

				# Skip ahead one extra byte.
				$j ++;
			}
			# Current and next byte are part of custom-mapped Shift-JIS pair.
			elsif($file_bytes[$j] eq "82" && hex($file_bytes[$j+1]) >= 32 && hex($file_bytes[$j+1]) <= 61)
			{
				# If beginning of byte array, set type and flag to string.
				if($j == 0)
				{
					$type_flag = "string";
					$string_chunks{$string_chunk_count}{'Type'} = 'String';
				}
				# If flag is set to control code, change to string and increase chunk count by one.
				elsif($type_flag eq "control_code")
				{
					$type_flag = "string";
					$string_chunk_count ++;
					$string_chunks{$string_chunk_count}{'Type'} = 'String';
				}

				# Translate custom Shift-JIS byte-pair to standard format (add 0x7F to second byte).
				$file_bytes[$j+1] = sprintf("%X", hex($file_bytes[$j+1]) + 127);

				# Append byte pair to current hash key's value.
				$string_chunks{$string_chunk_count}{'Value'} .= $file_bytes[$j] . $file_bytes[$j+1];

				# Skip ahead one extra byte.
				$j ++;
			}
			# Current byte is half-width Shift-JIS.
			elsif(exists $valid_shiftjis_half{uc($file_bytes[$j])} && $file_bytes[$j+1] ne "00")
			{
				# If beginning of byte array, set type and flag to string.
				if($j == 0)
				{
					$type_flag = "string";
					$string_chunks{$string_chunk_count}{'Type'} = 'String';
				}
				# If flag is set to control code, change to string and increase chunk count by one.
				elsif($type_flag eq "control_code")
				{
					$type_flag = "string";
					$string_chunk_count ++;
					$string_chunks{$string_chunk_count}{'Type'} = 'String';
				}

				# Append byte to current hash key's value.
				$string_chunks{$string_chunk_count}{'Value'} .= $file_bytes[$j];
			}
			# Current and next byte are a part of a mid-text control code.
			elsif($file_bytes[$j] eq "2a" && $file_bytes[$j+1] ne "00")
			{
				# If beginning of byte array, set type and flag to string.
				if($j == 0)
				{
					$type_flag = "string";
					$string_chunks{$string_chunk_count}{'Type'} = 'String';
				}
				# If flag is set to control code, change to string and increase chunk count by one.
				elsif($type_flag eq "control_code")
				{
					$type_flag = "string";
					$string_chunk_count ++;
					$string_chunks{$string_chunk_count}{'Type'} = 'String';
				}

				# Append byte pair to current hash key's value.
				$string_chunks{$string_chunk_count}{'Value'} .= $file_bytes[$j] . $file_bytes[$j+1];

				# Skip ahead one extra byte.
				$j ++;
			}
			# Current byte is ASCII-encoded text and not a control code.
			elsif(exists $valid_ascii{uc($file_bytes[$j])} && $file_bytes[$j+1] ne "00")
			{
				# If beginning of byte array, set type and flag to string.
				if($j == 0)
				{
					$type_flag = "string";
					$string_chunks{$string_chunk_count}{'Type'} = 'String';
				}
				# If flag is set to control code, change to string and increase chunk count by one.
				elsif($type_flag eq "control_code")
				{
					$type_flag = "string";
					$string_chunk_count ++;
					$string_chunks{$string_chunk_count}{'Type'} = 'String';
				}

				# Append byte to current hash key's value.
				$string_chunks{$string_chunk_count}{'Value'} .= $file_bytes[$j];
			}
			# Current byte is part of a control code in between text chunks.
			else
			{
				# If beginning of byte array, set type and flag to control code.
				if($j == 0)
				{
					$type_flag = "control_code";
					$string_chunks{$string_chunk_count}{'Type'} = 'Control Code';
				}
				# If flag is set to string, change to control code and increase chunk count by one.
				elsif($type_flag eq "string")
				{
					$type_flag = "control_code";
					$string_chunk_count ++;
					$string_chunks{$string_chunk_count}{'Type'} = 'Control Code';
				}

				# Append byte to current hash key's value.
				$string_chunks{$string_chunk_count}{'Value'} .= $file_bytes[$j];
			}
		}

		# Iterate through each string chunk key in the hash.
		foreach my $string_chunk_number (sort {$a <=> $b} keys %string_chunks)
		{
			# Store chunk type and value.
			my $chunk_type = $string_chunks{$string_chunk_number}{'Type'};
			my $chunk_value = $string_chunks{$string_chunk_number}{'Value'};

			# Status message.
			print "\nNumber: " . $string_chunk_number . "\n";
			print "Type: " . $chunk_type . "\n";
			print "Value: ";
			
			if($chunk_type eq "String")
			{
				print decode("shiftjis", pack "H*", $chunk_value) . "\n";
			}

			print $chunk_value . "\n";
		}

		# Store base archive name without file extension.
		(my $archive_base_name = $archive_name) =~ s/\.[^.]+$//;

		# Status message.
		print "\nWriting spreadsheet: " . $output_folder . "/" . $archive_base_name . "/" . $files[$i] . ".xls\n\n";

		# Write spreadsheet.
		mkdir($output_folder . "/" . $archive_base_name);
		&write_spreadsheet($archive_base_name, $files[$i], \%string_chunks);
	}
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

# Subroutine to generate hash mapping ASCII characters to custom hexadecimal values. Source character
# map file should be formatted with each character definition on its own line (<hex>|<ascii>). Example
# character map file:
#  ______
# |      |
# | 00|A |
# | 01|B |
# | 02|C |
# |______|
#
# The ASCII key in the returned hash will contain the custom hexadecimal value (e.g., $hash{'02'} will
# equal "C").
#
# 1st parameter - Full path of character map file.
sub generate_character_map_hash
{
	my $character_map_file = $_[0];
	my %character_table;

	open my $filehandle, '<', $character_map_file or die $!;
	chomp(my @mapped_characters = <$filehandle>);
	close $filehandle;

	foreach(@mapped_characters)
	{
		$character_table{(split /\|/, $_)[0]} = (split /\|/, $_)[1];
	}

	return %character_table;
}

# Subroutine to write spreadsheet.
sub write_spreadsheet
{
	my $archive_name = $_[0];
	my $filename = $_[1];
	my %string_chunks = %{$_[2]};

	my $workbook = Spreadsheet::WriteExcel->new($output_folder . "/" . $archive_name . "/" . $filename . ".xls");
	my $worksheet = $workbook->add_worksheet();
	my $header_bg_color = $workbook->set_custom_color(40, 191, 191, 191);

	my $header_format = $workbook->add_format();
	$header_format->set_bold();
	$header_format->set_border();
	$header_format->set_bg_color(40);

	my $cell_format = $workbook->add_format();
	$cell_format->set_border();
	$cell_format->set_align('left');
	$cell_format->set_text_wrap();

	my @character_names = ("N/A", "Takagi", "Takagi (internal)", "Aya", "Judy", "Rena", "Narrator", "Special1", "Special2", "Special3");
	$worksheet->data_validation('C2:C' . (keys(%string_chunks) + 1), { validate => 'list', value => [@character_names] });

	$worksheet->set_column('A:A', 14);
	$worksheet->set_column('B:B', 50);
	$worksheet->set_column('C:C', 17);
	$worksheet->set_column('D:D', 50);
	$worksheet->set_column('E:E', 40);
	$worksheet->set_column('F:F', 50);

	$worksheet->write(0, 0, "Type", $header_format);
	$worksheet->write(0, 1, "Value", $header_format);
	$worksheet->write(0, 2, "Speaker", $header_format);
	$worksheet->write(0, 3, "Translation", $header_format);
	$worksheet->write(0, 4, "Notes", $header_format);
	$worksheet->write(0, 5, "Machine Translation", $header_format);

	my $row_count = 1;

	foreach my $string_chunk_number (sort {$a <=> $b} keys %string_chunks)
	{
		my $type = $string_chunks{$string_chunk_number}{'Type'};
		my $value = $string_chunks{$string_chunk_number}{'Value'};

		my $machine_translation = "";
		my $api_call_success = 0;
		my $deepl_api_key = "25827b7d-27a3-4c14-c885-c92919ce1f5c";

		if($type eq "String")
		{
			while(!$api_call_success)
			{
				my $http = HTTP::Tiny->new;
				my $post_data = uri_encode("auth_key=" . $deepl_api_key . "&target_lang=EN-US&source_lang=JA&text=" . decode("shiftjis", pack "H*", $value));
				my $response = $http->get("https://api.deepl.com/v2/translate?" . $post_data);
				$machine_translation = decode_json($response->{'content'})->{'translations'}->[0]->{'text'};

				if($response->{'status'} eq "200")
				{
					$api_call_success = 1;
				}
			}
		}

		$worksheet->write($row_count, 0, $string_chunks{$string_chunk_number}{'Type'}, $cell_format);

		if($type eq "String")
		{
			$worksheet->write_utf16be_string($row_count, 1, Encode::encode("utf-16", decode("shiftjis", pack "H*", $value)), $cell_format);
		}
		else
		{
			$worksheet->write_string($row_count, 1, $value, $cell_format);
		}

		if($type eq "Control Code")
		{
			$worksheet->write($row_count, 2, "N/A", $cell_format);
		}
		else
		{
			$worksheet->write($row_count, 2, "", $cell_format);
		}
		
		$worksheet->write($row_count, 3, "", $cell_format);
		$worksheet->write($row_count, 4, "", $cell_format);
		$worksheet->write($row_count, 5, $machine_translation, $cell_format);
		
		$row_count ++;
	}

	$workbook->close();
}