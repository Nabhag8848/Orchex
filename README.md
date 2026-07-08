# Orchex

## Functional Requirement

Candidate: how the workflow should get trigger ? via webhooks, scheduler or manual.  
Interviewer: lets start with manual but should be extensible.

Candidate: what kind of nodes do we need to support ? Triggers, Integration Actions, General API Node,  
Conditional Nodes, Agent Node, Function Node, Scheduler, Response, Router ?  
Interviewer: At a minimum we will support General API Node, Conditional Node, Function Node, Integration Action Node & Response Node

Candidate: okay so we have nodes and edges, we must define how each nodes get connected to other nodes.  
directed, can their be cycle, can we have multiple branches from same node each branch runs concurrently, which all nodes can connect one, two and more than two node.  
Interviewer: we will have directed graph (from = to), and cycle is disallowed (DAG).

    Response Node = 1 Incoming, 0 Outgoing
    Start Node = 0 Incoming, 1 Outgoing
    Conditional Node = 1 Incoming, 2 Outgoing
    Function Node = 1 Incoming, 1 Outgoing
    General Api Node = 1 Incoming, 1 Outgoing
    Integration Action Node = 1 Incoming, 1 Outgoing

Candidate: this looks good, are we targeting to handle errors ? what if conditional node fails (incoming corrupted data), function node fails (execution failed for unknown reason), in integration action and api node, what if response with status other than 2\*\* (token expired, request time outs).  
Interviewer: we must handle this error gracefully.

Candidate: should we support atomic workflow execution, whole workflow rollback if one of the node fails and mark it as "FAILED" or we need to have an ability to start workflow from where it failed.  
Interviewer: for simplicity lets just have ability to start workflow from where it failed, if time persist we will talk about atomic workflow exection

Candidate: do we need to store node level traces and workflow level logs for each workflow ?  
Interviewer: lets store the workflow level logs and if time persist we will add node level traces.

Candidate: How many times workflows are run per day and how many combined user workflows we have ?  
Interviewer: 1M times/day , 100K combined workflows

Candidate: Do we need to assume we have Integrations and their Credentials already build by other team or we need to build it ?  
Interviewer: for simplicity just assume we already have Integration Infrastruture and Auth in Place. We will use Composio.

## Non Functional Requirements

**Reliability**  
- we should be able to start our workflow from where it failed.

**Scalability**  
- as we have assumed 100K workflows, 1M runs / day, then on average at least 10 workflow runs per day and nearly at any second nearly 10 are running.
    - 10 w/f running per day from 1M.
    - at any given second at least 10 w/f are running. QPS for new workflow run = 10 QPS, peak -> 10 * 10 = 100 QPS
    - 600 workflow per min if each of them takes 1 minute (we need to take care of disk I/O, concurrency as well as reliability)
    - as this is throughput intense. so it should be able to handle 600 workflows together at least and during peak 60K workflows together

**Read heavy or write heavy**  
- our system is write heavy. we log every state transition as well as have traces of what happened in each node of workflow, but we still have clear relation between entities.

    > relational databases are not generally good for write heavy operations, but to note our system is write heavy due to analytics, historic logs, traces of each node state transition, so we can use postgres for OLTP and clickhouse for OLAP.

**Eventual Consistency**  
- We need to achieve eventual consistency, few millisecond delays in traces and logs are fine.
