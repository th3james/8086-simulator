#!/usr/bin/env fish

zig build; and begin
  for binary_file in test-data/*.bin
      set source_file (string replace ".bin" ".asm" $binary_file)

      diff (./zig-out/bin/8086-simulator $binary_file | psub) $source_file
  end
end
