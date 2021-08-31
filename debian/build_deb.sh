#!/bin/bash
file_dir=$(dirname $(readlink -f $0))
parent="$file_dir/../build.zig"
zig build --build-file "$parent"
echo "Built binary"
mkdir -p "$file_dir/bcrypt-encoder/usr/bin"
cp "$file_dir/../zig-out/bin/main" "$file_dir/bcrypt-encoder/usr/bin/bcrypt-encoder"
major=0
minor=5
patch=0
version="$major.$minor.$patch"
size=123
sed -i "s/_VERSIONPLACEHOLDER_/$version/g" "$file_dir/bcrypt-encoder/DEBIAN/control"
sed -i "s/_SIZEPLACEHOLDER_/$size/g" "$file_dir/bcrypt-encoder/DEBIAN/control" 
echo "Prepared files"
cd "$file_dir"
dpkg-deb --build "bcrypt-encoder" && echo "Package built"
