import 'package:flutter/material.dart';
import 'package:zego_uikit_prebuilt_call/zego_uikit_prebuilt_call.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:zego_uikit_signaling_plugin/zego_uikit_signaling_plugin.dart';

class SpyCallService {
  static const int appID = 1206500765;// ZegoCloud AppID here
  static const String appSign = '1ee0960ffb2f98300a7562bb14ae465cfa1519c24d7d987ea2db41e09716de57'; // paste your AppSign here

  // Call this once in main.dart before runApp()
  static void init(String userID, String userName) {
    ZegoUIKitPrebuiltCallInvitationService().init(
      appID: appID,
      appSign: appSign,
      userID: userID,
      userName: userName,
      plugins: [ZegoUIKitSignalingPlugin()],
    );
  }

  // Call this in main.dart when app closes
  static void uninit() {
    ZegoUIKitPrebuiltCallInvitationService().uninit();
  }
}