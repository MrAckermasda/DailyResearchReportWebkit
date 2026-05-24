@{
    OutputDirectory = 'daily-digests'
    DashboardDataDirectory = 'data'
    WeeklyReportDirectory = 'weekly-reports'
    WeeklyReportTime = 'Sunday 20:00'
    KnowledgeTreeDirectory = 'knowledge-tree'
    ProjectDirectory = 'C:\Users\lunyi\Desktop\复合翼'
    DdlFileName = 'DDL清单.md'
    TaskName = 'LearningResearchDailyPush'
    Topics = @(
        @{
            Name = '无人机 / UAV'
            ArxivQuery = 'all:"unmanned aerial vehicle" OR all:drone OR all:quadrotor OR all:multirotor'
            GithubQuery = 'drone autopilot'
        },
        @{
            Name = '智能控制 / Intelligent Control'
            ArxivQuery = 'all:"intelligent control" OR all:"adaptive control" OR all:"model predictive control" OR all:"reinforcement learning control"'
            GithubQuery = 'intelligent control robotics'
        },
        @{
            Name = 'FOC 电机控制'
            ArxivQuery = 'all:"field oriented control" OR all:"vector control" OR all:PMSM OR all:"permanent magnet synchronous motor"'
            GithubQuery = '"field oriented control" motor'
        }
    )
    VideoFeeds = @(
        @{
            Name = 'PX4 Autopilot'
            Url = 'https://www.youtube.com/@PX4Autopilot/videos'
            Topic = '无人机 / UAV'
        },
        @{
            Name = 'ArduPilot'
            Url = 'https://www.youtube.com/@ArduPilot/videos'
            Topic = '无人机 / UAV'
        },
        @{
            Name = 'MIT OpenCourseWare'
            Url = 'https://www.youtube.com/@mitocw/videos'
            Topic = '智能控制 / Intelligent Control'
        },
        @{
            Name = 'ODrive Robotics'
            Url = 'https://www.youtube.com/@ODriveRobotics/videos'
            Topic = 'FOC 电机控制'
        },
        @{
            Name = 'SimpleFOC'
            Url = 'https://www.youtube.com/@SimpleFOC/videos'
            Topic = 'FOC 电机控制'
        }
    )
}
