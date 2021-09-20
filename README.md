# Miscellaneous Tools

This directory contains a list of tools I regularly use to troubleshoot performance. 

> Just because these tools work for me doesn't mean they work for you

The list of tools added is growing steadily while I port them from my private repositories.

## Overview

The tools added here usually deal with the Oracle database and surrounding ecosystem. As you know, the Oracle database
is propriatory software with a well-defined licensing framework. Violating the software license is NOT advised, and 
you need to be very careful not to do so. 

For the majority the tools listed here require the Oracle Database - Enterprise Edition. You may need extra licenses on
top of Enterprise Edition, especially when it comes to performance tools. 

> Before using any tool in this repository make sure you are appropriately licensed. 

Proceed only, and I can't stress this enough, if you are certain your database is licensed for the use of a given tool and/or
technology! I have been trying my best to point out license requirements in each tool, but I'm a techie, not a license person.
I can't and won't guarantee that I have been able to point out all license requirements, it is _your_ responsibility to ensure
license compliance.

It should also go without saying that you have to test the scripts on a non-production (read: low-key development) environment
first.

## Tools

The following table lists all the tools and their purpose

| Tool    | Purpose |
| ------- | ------- | 
| gen_awr_rpts_date | Generate AWR reports for single instance/Real Application Clusters for a given timeframe |
| gen_awr_rpts_snap | Generate AWR reports for single instance/Real Application Clusters for a given snapshot range |
| get_prefs.sql | Print the optimizer stats-gathering preferences for a table |
| sql_testcase.sql | Given a SQL ID and optionally a Plan Hash Value this script generates a SQL test case automatically |


## Contributing

At this point in time I'm not sure if I'll allow external contributions to this repository. Feel free to raise any questions you might 
have via Github issues and I'll take a look. 