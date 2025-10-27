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
	&& true

export NS3_VERSION=3.45

# SHA1s from the ns-3 release page
ns3_sha1=9b0bc3c3a35ec17e9afabbff86e3c1eef1d5fc91
ns_allinone_sha1=b47774dd89ec770a3bc88cf95251319aa0266afc

section ---------------- download ----------------
workdir /opt/ns-3
# Use ns-allinone to keep the old all-in-one layout (includes contributed modules)
run curl -L -o ../ns-allinone-$NS3_VERSION.tar.bz2 https://www.nsnam.org/releases/ns-allinone-$NS3_VERSION.tar.bz2
runsh "echo '${ns_allinone_sha1} ../ns-allinone-$NS3_VERSION.tar.bz2' | sha1sum -c"
run tar xj --strip-components 1 -f ../ns-allinone-$NS3_VERSION.tar.bz2

section ---------------- NetAnim ----------------
# NetAnim now uses CMake. build/bin/netanim is the produced binary.
workdir netanim-*
run mkdir -p build
workdir netanim-*/build
run cmake .. -G "Unix Makefiles"
run cmake --build . -- -j $(nproc)
run mkdir -p /ns-3-build/usr/local/bin
run cp build/bin/netanim /ns-3-build/usr/local/bin || true

section ---------------- ns-3 build ----------------
workdir "/opt/ns-3/ns-$NS3_VERSION"
# Configure & build with the ns3 wrapper (CMake under the hood).
# Enable python bindings (we'll capture the binding python tree afterwards).
run ./ns3 configure --enable-examples --enable-tests --enable-python-bindings
run ./ns3 build -j $(nproc)

# install libraries/executables into staging prefix so we can copy them into the wheel layout
run mkdir -p /ns-3-build/usr/local
run ./ns3 install --prefix=/ns-3-build/usr/local

section ---------------- prepare python wheel sources ----------------
# create a working packaging tree like your old script did
run mkdir -p /opt/ns-wheel
workdir /opt/ns-wheel

# copy your small hand-maintained wrapper package (assumes $base has your packaging files)
# keep the same pattern as your old script: copy __init__.py into staging site-packages, and prepare /opt/ns for bdist
run mkdir -p /ns-3-build/usr/local/lib/python3/dist-packages/ns
run cp "$base/__init__.py" /ns-3-build/usr/local/lib/python3/dist-packages/ns/

# Copy the ns Python bindings that ns-3 created into the packaging tree.
# The built python binding files live under: ns-3 build tree -> build/bindings/python/ns
# Find them and copy them into /opt/ns (source for setup.py)
run cp -r "/opt/ns-3/ns-$NS3_VERSION/build/bindings/python/ns" /opt/ns

# If the build used a different CMake cache folder, adjust the above path accordingly.

# Also copy the installed shared libs and helper executables into the final ns/_ layout
ns3_patch="patch/ns-$NS3_VERSION"
run rm -rf "$ns3_patch"
run mkdir -p "$ns3_patch/ns/_/lib" "$ns3_patch/ns/_/bin"

# Copy all installed ns-3 shared libraries into ns/_/lib
run cp /ns-3-build/usr/local/lib/libns3* "$ns3_patch/ns/_/lib/" || true
# Copy any other .so ns libraries (e.g., libpython helpers) if present
run cp /ns-3-build/usr/local/lib/*.so* "$ns3_patch/ns/_/lib/" || true || true

# Copy installed binaries that you want packaged (e.g., ns3 helper binaries) into ns/_/bin
run cp /ns-3-build/usr/local/bin/* "$ns3_patch/ns/_/bin/" || true

# Now copy the python package source into the patch dir (so wheel contains the same 'ns' package root)
run mkdir -p "$ns3_patch/ns"
run cp -r /opt/ns/* "$ns3_patch/ns/" || true
# Ensure __init__.py is present (from earlier copy)
run cp /ns-3-build/usr/local/lib/python3/dist-packages/ns/__init__.py "$ns3_patch/ns/" || true

section ---------------- replicate original wheel processing ----------------
# Now follow your old wheel manipulation steps: build a wheel skeleton, unpack, then fix rpaths the same way
# Create a temporary pure-Python wheel using your local setup (bdist_wheel) - this requires setup.py to exist in /opt/ns
workdir /opt/ns
# Create a source wheel as before
run python3 setup.py bdist_wheel

# Unpack the wheel to a mutable folder so we can inject the native libs
run python3 -m wheel unpack -d patch "dist/ns-$NS3_VERSION-py3-none-any.whl"

# Remove any nested python-version specific dir if present (old script did that)
run rm -r "$ns3_patch/ns/_/lib/python3" || true || true

# Move installed native libs/bins into the unpacked wheel layout:
# We already copied the built libs and bins into $ns3_patch/ns/_/{lib,bin}

# Fix rpaths exactly like your old script so the wheel is self-contained:
for f in "$ns3_patch"/ns/*.so; do
	patchelf --set-rpath '$ORIGIN/_/lib' "$f" || true
done

for f in "$ns3_patch"/ns/_/bin/*; do
	patchelf --set-rpath '$ORIGIN/../lib' "$f" || true
	chmod +x "$f" || true
done

for f in "$ns3_patch"/ns/_/lib/*.so*; do
	patchelf --set-rpath '$ORIGIN' "$f" || true
done

# Repack the wheel
run mkdir -p dist2
run python3 -m wheel pack -d dist2 "$ns3_patch"

asset_path="$base/ns-$NS3_VERSION-py3-none-linux_x86_64.whl"
run cp "dist2/ns-$NS3_VERSION-py3-none-any.whl" "$asset_path" || true

section ---------------- asset ----------------
asset "$asset_path"
