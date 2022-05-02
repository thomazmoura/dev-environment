echo "\n->> Installing Universal ctags"
git clone https://github.com/universal-ctags/ctags.git --depth 1
cd ctags
./autogen.sh
./configure
make
make install
