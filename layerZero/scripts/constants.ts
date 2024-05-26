//timestamp
export const A_MINUTES_SECONDS = 60;
export const A_HOUR_SECONDS = 60 * A_MINUTES_SECONDS;
export const A_DAY_SECONDS = 24 * A_HOUR_SECONDS;
export const A_WEEK_SECONDS = 7 * A_DAY_SECONDS;

//当前执行环境
export class ENV {
  static LOCAL_NET = "LOCAL_NET"; //本地环境
  static TEST_NET = "TEST_NET"; //测试链
  static MAIN_NET = "MAIN_NET"; //主网
}
