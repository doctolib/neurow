Code.require_file("integration_test/test_cluster_helper.exs")

Neurow.IntegrationTest.TestCluster.start_link()
ExUnit.start()
