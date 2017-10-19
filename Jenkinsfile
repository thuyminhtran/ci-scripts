#!/usr/bin/env groovy
// -*- mode: groovy; tab-width: 2; groovy-indent-offset: 2 -*-
// Copyright (c) 2017 Wind River Systems Inc.
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

node('docker') {

  // function for adding array of env vars to string
  def add_env = {
    String command, String[] env_args ->
    for ( arg in env_args ) {
      command = command + " -e ${arg} "
    }
    return command
  }

  // Node name is from docker swarm is hostname + dash + random string. Remove random part of recover hostname
  def hostname = "${NODE_NAME}"
  hostname = hostname[0..-10]
  def common_docker_params = "--rm --name build-${BUILD_ID} --hostname ${hostname} -t --tmpfs /tmp --tmpfs /var/tmp -v /etc/localtime:/etc/localtime:ro -u 1000 -v ci_jenkins_agent:/home/jenkins -e LANG=en_US.UTF-8 -e BUILD_ID=${BUILD_ID} -e WORKSPACE=${WORKSPACE} "

  stage('Docker Run Check') {
    dir('ci-scripts') {
      git(url:params.CI_REPO, branch:params.CI_BRANCH)
    }
    sh "${WORKSPACE}/ci-scripts/docker_run_check.sh"
  }
  stage('Cache Sources') {
    dir('ci-scripts') {
      git(url:params.CI_REPO, branch:params.CI_BRANCH)
    }
    def env_args = ["BASE=${WORKSPACE}", "REMOTE=${REMOTE}"]
    def docker_params = add_env( common_docker_params, env_args )
    def cmd="${WORKSPACE}/ci-scripts/wrlinux_update.sh ${BRANCH}"
    sh "docker run ${docker_params} ${REGISTRY}/${IMAGE} ${cmd}"
  }

  try {
    stage('Layerindex Setup') {
      // if devbuilds are enabled, start build in same network as layerindex
      if (params.DEVBUILD_ARGS != "") {
        dir('ci-scripts') {
          git(url:params.CI_REPO, branch:params.CI_BRANCH)
        }
        devbuild_args = params.DEVBUILD_ARGS.tokenize(',')
        withEnv(devbuild_args) {
          dir('ci-scripts/layerindex') {
            sh "./layerindex_start.sh"
            sh "./layerindex_layer_update.sh"
          }
        }
      }
      else {
        println("Not starting local LayerIndex")
      }
    }

    stage('Build') {
      dir('ci-scripts') {
        git(url:params.CI_REPO, branch:params.CI_BRANCH)
      }

      def docker_params = common_docker_params
      def env_args = ["MESOS_TASK_ID=${BUILD_ID}", "BASE=${WORKSPACE}"]
      if (params.TOASTER == "enable") {
        docker_params = docker_params + ' --expose=8800 -P '
        env_args = env_args + ["SERVICE_NAME=toaster", "SERVICE_CHECK_HTTP=/health"]
      }

      if (params.DEVBUILD_ARGS != "") {
        docker_params = docker_params + ' --network=build${BUILD_ID}_default'
        env_args = env_args + params.DEVBUILD_ARGS.tokenize(',')
      }

      env_args = env_args + ["NAME=${NAME}", "BRANCH=${BRANCH}"]
      env_args = env_args + ["NODE_NAME=${NODE_NAME}", "SETUP_ARGS=\'${SETUP_ARGS}\'"]
      env_args = env_args + ["PREBUILD_CMD=\'${PREBUILD_CMD}\'", "BUILD_CMD=\'${BUILD_CMD}\'", "TOASTER=${TOASTER}"]
      docker_params = add_env( docker_params, env_args )
      def cmd="${WORKSPACE}/ci-scripts/jenkins_build.sh"
      sh "docker run ${docker_params} ${REGISTRY}/${IMAGE} ${cmd}"
    }
  } finally {
    stage('Layerindex Cleanup') {
      if (params.DEVBUILD_ARGS != "") {
        dir('ci-scripts') {
          git(url:params.CI_REPO, branch:params.CI_BRANCH)
        }
        dir('ci-scripts/layerindex') {
          sh "./layerindex_stop.sh"
        }
      }
      else {
        println("No LayerIndex Cleanup necessary")
      }
    }
  
    stage('Post Process') {
      dir('ci-scripts') {
        git(url:params.CI_REPO, branch:params.CI_BRANCH)
      }
      def docker_params = common_docker_params + " --network=rsync_net "
      def env_args = ["NAME=${NAME}"]
      env_args = env_args + ["POST_SUCCESS=${POST_SUCCESS}", "POST_FAIL=${POST_FAIL}"]
      env_args = env_args + params.POSTPROCESS_ARGS.tokenize(',')
      docker_params = add_env( docker_params, env_args )
      def cmd="${WORKSPACE}/ci-scripts/build_postprocess.sh"
      sh "docker run --init ${docker_params} ${REGISTRY}/${POSTPROCESS_IMAGE} ${cmd}"
    }
  }

  try {
    stage('Test') {
      if (params.TEST == 'enable') {
        dir('ci-scripts') {
          git(url:params.CI_REPO, branch:params.CI_BRANCH)
        }
        def docker_params = common_docker_params
        def env_args = ["NAME=${NAME}"]
        env_args = env_args + params.TEST_ARGS.tokenize(',')
        docker_params = add_env( docker_params, env_args )
        def cmd="${WORKSPACE}/ci-scripts/run_tests.sh"
        sh "docker run --init ${docker_params} ${REGISTRY}/${TEST_IMAGE} ${cmd}"
      } else {
        println("Test disabled")
      }
    }
  } finally {
    stage('Post Test') {
      if (params.TEST == 'enable') {
        dir('ci-scripts') {
          git(url:params.CI_REPO, branch:params.CI_BRANCH)
        }
        def docker_params = common_docker_params
        def env_args = ["NAME=${NAME}"]
        env_args = env_args + ["POST_TEST_SUCCESS=${POST_TEST_SUCCESS}", "POST_TEST_FAIL=${POST_TEST_FAIL}"]
        env_args = env_args + params.TEST_ARGS.tokenize(',')
        docker_params = add_env( docker_params, env_args )
        def cmd="${WORKSPACE}/ci-scripts/test_postprocess.sh"
        sh "docker run --init ${docker_params} ${REGISTRY}/${POST_TEST_IMAGE} ${cmd}"
      } else {
        println("Test disabled")
      }
    }
  }
}
