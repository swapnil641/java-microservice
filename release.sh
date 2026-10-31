
#!/bin/bash

set -e

TYPE=$1

if [[ "$TYPE" != "major" && "$TYPE" != "minor" && "$TYPE" != "patch" ]]; then
    echo "Usage: ./release.sh [major|minor|patch]"
    exit 1
fi

VERSION=$(python3 - <<'PY'
import re

with open("pom.xml") as f:
    content = f.read()

match = re.search(
    r'(<artifactId>java-microservice</artifactId>\s*<version>)([^<]+)(</version>)',
    content
)

if not match:
    raise SystemExit("Could not find project version in pom.xml")

print(match.group(2))
PY
)

IFS='.' read -r MAJOR MINOR PATCH <<< "$VERSION"

case "$TYPE" in
    major)
        ((MAJOR+=1))
        MINOR=0
        PATCH=0
        ;;
    minor)
        ((MINOR+=1))
        PATCH=0
        ;;
    patch)
        ((PATCH+=1))
        ;;
esac

NEW_VERSION="$MAJOR.$MINOR.$PATCH"

python3 - "$NEW_VERSION" <<'PY'
import re
import sys

new_version = sys.argv[1]

with open("pom.xml") as f:
    content = f.read()

content = re.sub(
    r'(<artifactId>java-microservice</artifactId>\s*<version>)[^<]+(</version>)',
    lambda m: m.group(1) + new_version + m.group(2),
    content,
    count=1
)

with open("pom.xml", "w") as f:
    f.write(content)
PY

echo "Version updated: $VERSION -> $NEW_VERSION"

mvn clean package

mkdir -p releases
cp "target/java-microservice-$NEW_VERSION.jar" releases/

echo "Release completed: java-microservice-$NEW_VERSION.jar"
