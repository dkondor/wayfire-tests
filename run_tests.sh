#!/bin/sh

# Add colors for nicer output
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CLR='\033[0m'

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
RUN_GUI_TESTS=0

# ----------------------------- Check arguments --------------------------------
function print_usage {
    printf "Usage: ./run_tests.sh <test directory> <wayfire A> (<wayfire B>)\n"
    exit -1
}

echo $#
if ! [ -d "$1" ] || ! [ -x "$2" ] || (( $# > 3 )) || (( $# < 2 )); then
    if [ $# > 3 ]; then
        echo here
    fi
    print_usage
    exit -1
fi

if (( $# == 3 )); then
    if ! [ -x "$3" ]; then
        print_usage
        exit -1
    fi

    if ! [ -x "grim" ]; then
        printf "emersion/grim not found in \$PATH, cannot run GUI tests.\n"
        exit -1
    fi

    printf "Running ${BLUE}GUI${CLR} tests.\n"
fi

# Add test helper to pythonpath so that python tests can find it
export PYTHONPATH=$PYTHONPATH:$SCRIPT_DIR/wfpyipc

# -------------------------------- Run tests -----------------------------------
printf "Running tests in directory ${YELLOW}$(pwd)/$1${CLR}\n"

# Make sure that tests can see the proper exit codes!
source $SCRIPT_DIR/tests/exitcodes.sh

# Check whether test has valid format
# If not, fail
# $1 - test directory
function check_test() {
    if ! [ -x $1/main ] || ! [ -f $1/options.sh ] || ! [ -f $1/wayfire.ini ]; then
        printf "${RED}Test $1 has invalid format, fix it and retry again!\n"
        exit -1
    fi
}

# $1 - test directory
# $? - whether to run test or skip
function prepare_test() {
    source $1/options.sh

    if [ $RUN_GUI_TESTS -ne $IS_GUI_TEST ]; then
        printf "Test ${testdir} is GUI test - "
        return $WF_TEST_SKIP
    else
        printf "Running test ${BLUE}${testdir}${CLR} - "
        return $WF_TEST_OK
    fi
}

# $1 - test directory
# $2 - wayfire executable
# $? - test result
function execute_simple_test() {
    $2 -c $1/wayfire.ini &> $1/wayfire.log &
    wayfire_pid=$!
    $1/main
    teststatus=$?
    kill -9 $wayfire_pid &> /dev/null
    return $teststatus
}

# $1 - test directory
# $2 - wayfire executable
# $3 - output file name
# $? - test result
function execute_gui_test_once() {
    $2 -c $1/wayfire.ini &> $1/wayfire.log &
    wayfire_pid=$!
    $1/main
    if ! [ $? -eq $WF_TEST_OK ]; then
        return $teststatus
    fi

    ./wfscreenshot.py $3
    if ! [ $? -eq 0 ]; then
        return $WF_TEST_CRASH
    fi
    kill -9 $wayfire_pid &> /dev/null
    return 0
}

# $1 - test directory
# $2 - wayfire executable 1
# $3 - wayfire executable 2
# $? - test result
function execute_gui_test() {
    file1=$1/wayfire_a.png
    file2=$1/wayfire_b.png

    execute_gui_test_once $1 $2 $file1
    if ! [ $? -eq 0 ]; then
        return $WF_TEST_CRASH
    fi

    execute_gui_test_once $1 $3 $file2
    if ! [ $? -eq 0 ]; then
        return $WF_TEST_CRASH
    fi



    return $teststatus
}

test_ok=0
test_notok=0
test_skipped=0

for testdir in $(find $1 -type d); do
    # Check only directories which have a main entry point
    if ! [ -x "$testdir/main" ]; then
        continue
    fi

    check_test $testdir
    prepare_test $testdir
    status=$?

    if [ $status -eq $WF_TEST_OK ]; then
        execute_simple_test $testdir $2
        status=$?
    fi

    case $status in
        $WF_TEST_OK)
            printf "${GREEN}OK"
            test_ok=$(($test_ok + 1))
            ;;
        $WF_TEST_WRONG)
            printf "${RED}WRONG"
            test_notok=$(($test_notok + 1))
            ;;
        $WF_TEST_SKIP)
            printf "${YELLOW}SKIPPED"
            test_skipped=$(($test_skipped + 1))
            ;;
        $WF_TEST_CRASH)
            printf "${RED}CRASH"
            test_notok=$(($test_notok + 1))
            ;;
        *)
            printf "${RED}Unknown (test crashed?)"
            test_notok=$(($test_notok + 1))
            ;;
    esac
    printf "${CLR}\n"
done

# -------------------------------- Summary -------------------------------------
test_total=$(($test_ok + $test_skipped + $test_notok))

text_ok="${GREEN}${test_ok} ok${CLR}"
text_notok="${test_ok} not ok"
text_skipped="${test_skipped} skipped"

if (($test_notok > 0)); then
    text_ok="${BLUE}${test_ok} ok${CLR}"
    text_notok="${RED}${test_notok} not ok${CLR}"
fi

if (($test_skipped > 0)); then
    text_skipped="${YELLOW}${test_skipped} skipped${CLR}"
fi

printf "Test summary: $text_ok / $text_notok / $text_skipped (total: ${test_total})\n"
