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

needrepocheck=0
# loop againts files
for FILE in $FILES
do
	case $FILE in
	(*.go)  # ! == does match
	    servicecheckpoint=0
	    for SERVICE in $SERVICES
	    do
	        case $FILE  in
	        *"$SERVICE"*)
	            matrixtocheck["$SERVICE"]=1
                ((servicecheckpoint=servicecheckpoint+1))
	        ;;
	        *)
	            matrixtocheck["$SERVICE"]=0 ;;
	        esac
	    done
	    if [ $servicecheckpoint -ne 0 ]; then
            ((needrepocheck=needrepocheck+1))
	    fi
	esac
done

if [ $needrepocheck -eq 0 ]; then
	echo "Changges applied to outside service, starting test..."
    # repo tests
	repowide="./..."
	go test -v $(echo "$repowide") | tee test-repowide.out
	if [ ${PIPESTATUS[0]} -ne 0 ]; then
        ((haserror=haserror+1))
	    failedtest[${#failedtest[@]}]="repowide"
    fi
else
    for SERVICE in "${!matrixtocheck[@]}"
    do
        echo "Checking changes inside [$SERVICE]"
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
                    failedtest[${#failedtest[@]}]="usecase"
                fi
                # web infra tests
                web="./infrastructure/service/internal_/web/api/$SERVICE/..."
                go test -v $(echo "$web") | tee test-web.out
                if [ ${PIPESTATUS[0]} -ne 0 ]; then
                    ((haserror=haserror+1))
                    failedtest[${#failedtest[@]}]="web"
                fi
            ;;
            esac
        done
    done
fi

if [ $haserror -ne 0 ]; then
    echo "Warning! Some of unit tests failed. Test results are written in test-db.out, test-usecase.out, test-web.out, or test-repowide.out. Please check!"
    for value in "${failedtest[@]}"
    do
        echo "hint: $value"
    done
    exit 1
fi

echo "All unit tests passed, continue pushing to repository..."
