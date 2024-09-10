Code.require_file("integration_test/test_cluster.exs")

Neurow.IntegrationTest.TestCluster.start_link()
ExUnit.start()
