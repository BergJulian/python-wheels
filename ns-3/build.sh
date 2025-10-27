#!/usr/bin/env bash
set -euo pipefail

repo="$PWD"
base="$repo/ns-3"

section ---------------- install ----------------
run apt-get update
run apt-get install -y --no-install-recommends \
	bzip2 \
	cmake \
	curl \
	g++ \
	git \
	libclang-dev \
	llvm-dev \
	make \
	patch \
	patchelf \
	python3-dev \
	python3-pip \
	python3-setuptools \
	python3-wheel \
	qtbase5-dev \
	ninja-build \
	zip \
	# Boost headers & libs required by some contrib modules (e.g., uart-net-device)
	libboost-all-dev \
	# libxml2 is often used; ensure headers present
	libxml2-dev \
	&& true

export NS3_VERSION=3.45

# Use the ns-allinone archive to preserve "all-in-one" layout (contribs etc.)
ns_allinone_sha1=b47774dd89ec770a3bc88cf95251319aa0266afc

section ---------------- download ----------------
workdir /opt/ns-3
run curl -L -o ../ns-allinone-$NS3_VERSION.tar.bz2 https://www.nsnam.org/releases/ns-allinone-$NS3_VERSION.tar.bz2
runsh "echo '${ns_allinone_sha1} ../ns-allinone-$NS3_VERSION.tar.bz2' | sha1sum -c"
run tar xj --strip-components 1 -f ../ns-allinone-$NS3_VERSION.tar.bz2

section ---------------- NetAnim ----------------
# Robust NetAnim build: find the real netanim-* directory and build with CMake
workdir /opt/ns-3
run bash -eux -c '
# choose first netanim-* dir found
netanim_dir="$(ls -d netanim-* 2>/dev/null | head -n1 || true)"
if [ -z "$netanim_dir" ] || [ ! -d "$netanim_dir" ]; then
  echo "ERROR: no netanim-* directory found under /opt/ns-3"
  ls -la /opt/ns-3
  exit 1
fi
echo "Building NetAnim in: $netanim_dir"
pushd "$netanim_dir"
# out-of-source build
mkdir -p build
cd build
cmake .. -G "Unix Makefiles"
cmake --build . -- -j"$(nproc)"
# copy binary if produced
mkdir -p /ns-3-build/usr/local/bin
if [ -x "bin/netanim" ]; then
  cp "bin/netanim" /ns-3-build/usr/local/bin/
elif [ -x "netanim" ]; then
  cp "netanim" /ns-3-build/usr/local/bin/
else
  find . -type f -name "netanim" -executable -exec cp {} /ns-3-build/usr/local/bin/ \; || true
fi
popd
'

section ---------------- ns-3 ----------------
workdir "/opt/ns-3/ns-$NS3_VERSION"
# Remove any stale caches to ensure CMake picks up new deps and prefix
run rm -rf cmake-cache build || true

# Configure with desired install prefix so `./ns3 install` will place files into /ns-3-build/usr/local
run ./ns3 configure --prefix=/ns-3-build/usr/local --enable-examples --enable-tests --enable-python-bindings
run ./ns3 build -j "$(nproc)"

workdir "/opt/ns-3/ns-$NS3_VERSION"
run mkdir -p /ns-3-build/usr/local
# Install to the configured prefix
run ./ns3 install

section ---------------- python wheel (preserve exact layout) ----------------
# Prepare packaging tree and create the wheel in the exact style you used previously.
workdir /opt/ns
run rm -rf /opt/ns || true
run mkdir -p /opt/ns

# Copy user ns package skeleton from repo (expects repo/ns-3 contains __init__.py and ns/ dir)
run cp "$base/__init__.py" /ns-3-build/usr/local/lib/python3/dist-packages/ns/ || true
run cp -r "$base/ns" /opt/ns || true

# Create a local wheel using setup.py from /opt/ns (bdist_wheel produces a pure-python wheel we will inject native libs into)
workdir /opt/ns
run python3 -m pip install --upgrade pip wheel setuptools
run python3 setup.py bdist_wheel

# Unpack the wheel so we can inject native libs and binaries (same approach as original script)
workdir /opt/ns
run python3 -m wheel unpack -d patch "dist/ns-$NS3_VERSION-py3-none-any.whl"

# Create patch dir structure matching your original wheel layout
run ns3_patch="patch/ns-$NS3_VERSION"
run rm -rf "$ns3_patch" || true
run mkdir -p "$ns3_patch/ns/_/lib" "$ns3_patch/ns/_/bin"

# Copy the python binding sources that ns-3 produced (runtime-binding stubs)
# These are usually under build/bindings/python/ns relative to the ns-3 source/build dir
run cp -r "/opt/ns-3/ns-$NS3_VERSION/build/bindings/python/ns" "$ns3_patch/ns/" || true

# Copy installed native shared libraries (C++ libs) into the wheel layout
# Copy from the install prefix (both lib and lib64 to be safe)
run cp -v /ns-3-build/usr/local/lib/libns3* "$ns3_patch/ns/_/lib/" 2>/dev/null || true
run cp -v /ns-3-build/usr/local/lib/*.so* "$ns3_patch/ns/_/lib/" 2>/dev/null || true || true
run cp -v /ns-3-build/usr/local/lib64/*.so* "$ns3_patch/ns/_/lib/" 2>/dev/null || true || true

# Copy installed helper binaries into ns/_/bin (some ns tools, optional)
run cp -v /ns-3-build/usr/local/bin/* "$ns3_patch/ns/_/bin/" 2>/dev/null || true || true

# Ensure the top-level Python package files are present in the patch (use the one we copied earlier)
run mkdir -p "$ns3_patch/ns"
run cp -v /ns-3-build/usr/local/lib/python3/dist-packages/ns/__init__.py "$ns3_patch/ns/" 2>/dev/null || true

# Remove any nested python-version specific directories that might conflict (replicating your original cleanup)
run rm -rf "$ns3_patch/ns/_/lib/python3" || true || true

# Fix rpaths exactly like your old script so the wheel is self-contained:
run bash -eux -c '
ns3_patch="patch/ns-$NS3_VERSION"
# adjust rpath for .so files at top-level ns/*.so (if any)
for f in "$ns3_patch"/ns/*.so*; do
  [ -f "$f" ] || continue
  patchelf --set-rpath '"'"'$ORIGIN/_/lib'"'"' "$f" || true
done
# adjust rpath for helper executables in ns/_/bin
for f in "$ns3_patch"/ns/_/bin/*; do
  [ -f "$f" ] || continue
  patchelf --set-rpath '"'"'$ORIGIN/../lib'"'"' "$f" || true
  chmod +x "$f" || true
done
# adjust rpath for libs in ns/_/lib
for f in "$ns3_patch"/ns/_/lib/*.so*; do
  [ -f "$f" ] || continue
  patchelf --set-rpath '"'"'$ORIGIN'"'"' "$f" || true
done
'

# Repack the wheel containing the injected native libs
workdir /opt/ns
run mkdir -p dist2
run python3 -m wheel pack -d dist2 "$ns3_patch"

# Copy artifact to repo in the same path as your original asset expected
asset_path="$base/ns-$NS3_VERSION-py3-none-linux_x86_64.whl"
run mkdir -p "$(dirname "$asset_path")"
run cp "dist2/ns-$NS3_VERSION-py3-none-any.whl" "$asset_path"

section ---------------- post-build notes ----------------
# Make sure cppyy is installed at runtime where the wheel will be used (cppyy is needed to load C++ introspection)
run python3 -m pip install --no-cache-dir cppyy || true

section ---------------- asset ----------------
asset "$asset_path"
