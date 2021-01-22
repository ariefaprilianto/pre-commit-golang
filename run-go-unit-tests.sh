#!/usr/bin/env bash
haserror=0
branch=$(git branch | sed -n -e 's/^\* \(.*\)/\1/p')
remotebanch="origin/$branch"
root=$(pwd)

echo "Checking changes in $remotebanch"

SERVICES=$(ls -l cmd/http | grep ^d | awk '{print $10}')
FILES=$(git diff --stat --cached $remotebanch)
declare -A matrixtocheck
declare -A failedtest

# loop againts services
for SERVICE in $SERVICES
do
  matrixtocheck["$SERVICE"]=0
done

# loop againts files
for FILE in $FILES
do
  case $FILE in
    (*.go)  # ! == does not match
      for SERVICE in $SERVICES
      do
        case $FILE  in
          *"$SERVICE"*)
            matrixtocheck["$SERVICE"]=1 ;;
          *)
            matrixtocheck["$SERVICE"]=0 ;;
        esac
      done
  esac
done

for SERVICE in $SERVICES
do
  for val in "${matrixtocheck[$SERVICE]}"; do
      case $val in
      1)
          echo "Changges applied to [$SERVICE] service, starting test..."

          # database tests
          db="./infrastructure/database/$SERVICE/..."
          go test -v $(echo "$db") | tee test-db.out
          if [ ${PIPESTATUS[0]} -ne 0 ]; then
            ((haserror=haserror+1))
            failedtest[${#failedtest[@]}]="database"
          fi
          # usecase tests
          usecase="./usecase/$SERVICE/..."
          go test -v $(echo "$usecase") | tee test-usecase.out
          if [ ${PIPESTATUS[0]} -ne 0 ]; then
            ((haserror=haserror+1))
            failedtest[${#failedtest[@]}]="database"
          fi
          # web infra tests
          web="./infrastructure/service/internal_/web/api/$SERVICE/..."
          go test -v $(echo "$web") | tee test-web.out
          if [ ${PIPESTATUS[0]} -ne 0 ]; then
            ((haserror=haserror+1))
             failedtest[${#failedtest[@]}]="database"
          fi


          ;;
      *)
      esac
  done
done

if [ $haserror -ne 0 ]; then
  echo "Warning! Some of unit tests failed. Please check!"
  for value in "${failedtest[@]}"
  do
      echo "hint: $value"
  done
  exit 1
fi