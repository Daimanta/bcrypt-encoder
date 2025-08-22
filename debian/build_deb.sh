#!/bin/bash
file_dir=$(dirname $(readlink -f $0))
parent="$file_dir/../build.zig"
zig build --build-file "$parent"
echo "Built binary"
mkdir -p "$file_dir/bcrypt-encoder/usr/bin"
cp "$file_dir/../zig-out/bin/bcrypt-encoder" "$file_dir/bcrypt-encoder/usr/bin/bcrypt-encoder"
version=$(cat "$file_dir/../src/version.zig" | cut -d" " -f6 | tr -d ";" | sed ':a; N; $!ba; s/\n/./g')
size=$(du -sb "$file_dir/bcrypt-encoder/usr/bin/bcrypt-encoder" | cut -f1)
sed -i "s/_VERSIONPLACEHOLDER_/$version/g" "$file_dir/bcrypt-encoder/DEBIAN/control"
sed -i "s/_SIZEPLACEHOLDER_/$size/g" "$file_dir/bcrypt-encoder/DEBIAN/control" 
echo "Prepared files"
cd "$file_dir"
dpkg-deb --build --root-owner-group "bcrypt-encoder" && echo "Package built"
