rm -rf tmp
mkdir tmp
cd tmp

echo "version:"
npx --registry http://localhost:4873 @ziex/cli@dev version
echo -e "\ninit:"
npx --registry http://localhost:4873 @ziex/cli@dev init