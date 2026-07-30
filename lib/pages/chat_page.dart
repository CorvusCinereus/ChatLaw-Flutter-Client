/**
 * @file chat_page.dart
 * @brief 聊天页面
 * @author CorvusCinereus
 */

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:chatlaw/internal/config.dart';
import "package:flutter_chat_bubble/chat_bubble.dart";
import 'package:chatlaw/pages/dialog.dart';
import 'package:chatlaw/pages/page_index.dart';
import 'package:step_progress/step_progress.dart';

class ChatPage extends StatefulWidget {
  final AppConfig _appConfig;
  final String _serverName;
  final Function(PageIndex page, {String? serverName}) _setPage;
  final Function(Map<String, dynamic> history) _addHistory;
  final Function(String name) _removeHistory;
  final Function(LawCache cache) _addCache;
  final Function(String oldName, String newName) _renameCache;

  const ChatPage({
    super.key,
    required this._appConfig,
    required this._serverName,
    required this._setPage,
    required this._addHistory,
    required this._removeHistory,
    required this._addCache,
    required this._renameCache,
  });

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage>
    with SingleTickerProviderStateMixin {
  int _serverIndex = -1;
  String _historyName = "未命名对话";
  bool _showDetail = false;
  bool _recording = false;
  List<Map<String, dynamic>> _history = [];
  List<String> _caches = [];
  List<String> _details = [];
  final TextEditingController _messageController = TextEditingController();
  final StepProgressController _stepProgressController = StepProgressController(
    totalSteps: 4,
  );

  bool _isDrawerOpen = false;
  late AnimationController _animationController;
  List<Widget>? _drawerItems;

  @override
  void initState() {
    super.initState();
    _serverIndex = widget._appConfig.serverConfigs.indexWhere(
      (element) => element.name == widget._serverName,
    );
    if (_serverIndex == -1) {
      showAlertDialog(
        context,
        "服务器不存在",
        textStyle: widget._appConfig.textStyle,
      );
      widget._setPage(PageIndex.start);
    } else {
      setState(() {
        _history = [];
      });
      _animationController = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 300),
      );
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  /// @brief 切换抽屉状态
  void _toggleDrawer() {
    if (!_showDetail) {
      setState(() {
        _isDrawerOpen = !_isDrawerOpen;
        if (_isDrawerOpen) {
          _animationController.forward();
        } else {
          _animationController.reverse();
        }
      });
    }
  }

  /// @brief 关闭抽屉
  void _closeDrawer() {
    if (_isDrawerOpen) {
      setState(() {
        _isDrawerOpen = false;
        _animationController.reverse();
      });
    }
  }

  List<Widget> _buildDrawerItems() {
    if (_drawerItems != null) {
      return _drawerItems!;
    }

    final historyList = widget._appConfig.history;
    if (historyList.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            '暂无历史记录',
            style: TextStyle(
              color: Colors.grey,
              fontSize: widget._appConfig.textStyle.fontSize,
            ),
          ),
        ),
      ];
    }

    return historyList.map<Widget>((item) {
      final title = item["name"] ?? "未命名对话";
      return ListTile(
        leading: const Icon(Icons.chat, color: Colors.black),
        title: Row(
          spacing: 5,
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(color: Colors.black),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            PopupMenuButton(
              child: IconButton(
                onPressed: null,
                icon: const Icon(Icons.more_vert, color: Colors.black),
              ),
              itemBuilder: (BuildContext context) => <PopupMenuEntry>[
                PopupMenuItem(
                  value: 1,
                  child: ListTile(
                    leading: const Icon(Icons.edit),
                    title: Text("重命名对话", style: widget._appConfig.textStyle),
                  ),
                ),
                PopupMenuItem(
                  value: 2,
                  child: ListTile(
                    leading: const Icon(Icons.delete),
                    title: Text("删除对话", style: widget._appConfig.textStyle),
                  ),
                ),
              ],
              onSelected: (value) async {
                if (value == 1) {
                  final TextEditingController newNameController =
                      TextEditingController();

                  String? newName = await showDialog<String>(
                    context: context,
                    barrierDismissible: false,
                    builder: (BuildContext context) => AlertDialog(
                      title: const Icon(Icons.edit),
                      content: TextField(
                        controller: newNameController,
                        autofocus: true,
                        decoration: const InputDecoration(
                          hintText: "请输入新对话名称",
                          border: OutlineInputBorder(),
                        ),
                        onSubmitted: (value) {
                          Navigator.of(context).pop(value);
                        },
                      ),
                      actions: [
                        // 取消按钮
                        TextButton(
                          onPressed: () {
                            Navigator.of(context).pop(); // 返回 null
                          },
                          child: const Text('取消'),
                        ),
                        // 确认按钮
                        ElevatedButton(
                          onPressed: () {
                            // 点击确认时，将输入框的内容作为结果返回
                            Navigator.of(context).pop(newNameController.text);
                          },
                          child: const Text('确定'),
                        ),
                      ],
                    ),
                  );
                  if (newName != null) {
                    if (widget._appConfig.history.indexWhere(
                          (element) => element['name'] == newName,
                        ) !=
                        -1) {
                      newName += '#';
                    }
                    setState(() {
                      widget._renameCache(_historyName, newName!);
                      _historyName = newName;
                      item["name"] = newName;
                      widget._addHistory(item);
                    });
                  }
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    newNameController.dispose();
                  });
                } else if (value == 2 &&
                    await showAskDialog(context, "是否删除该对话?")) {
                  setState(() {
                    _history = [];
                    _historyName = "未命名对话";
                    widget._removeHistory(title);
                    _closeDrawer();
                  });
                }
              },
            ),
          ],
        ),
        onTap: () {
          _closeDrawer();
          setState(() {
            _historyName = item["name"] ?? "未命名对话";
            _history = (item["history"] as List? ?? [])
                .whereType<Map<String, dynamic>>()
                .toList();

            // 加载缓存
            final index = widget._appConfig.lawCaches.indexWhere(
              (element) => element.name == _historyName,
            );
            if (index != -1) {
              _caches = widget._appConfig.lawCaches[index].laws;
              _details = widget._appConfig.lawCaches[index].details;
              if (_caches.isNotEmpty) {
                _stepProgressController.setCurrentStep(3);
              }
            }
          });
        },
      );
    }).toList();
  }

  void _sendMessage(String message) {
    _stepProgressController.setCurrentStep(-1); // 重置进度条
    _caches = [];

    setState(() {
      if (_historyName == "未命名对话") {
        String name = message.length < 7 ? message : message.substring(0, 6);
        if (widget._appConfig.history.indexWhere(
              (element) => element["name"] == name,
            ) !=
            -1) {
          name += "#";
        }
        _historyName = name;
      }
      _history.add({"role": "user", "content": message});
      _showDetail = true;
      _startProgress();
    });
    widget._addHistory({"name": _historyName, "history": _history});
  }

  @override
  Widget build(BuildContext context) {
    // 遮罩层（点击关闭）
    Widget overlay = Positioned.fill(
      child: FadeTransition(
        opacity: _animationController,
        child: IgnorePointer(
          ignoring: !_isDrawerOpen, // 关闭时忽略点击，避免误触
          child: GestureDetector(
            onTap: _closeDrawer,
            child: Container(color: Colors.black54),
          ),
        ),
      ),
    );

    // 抽屉面板
    Widget drawer = AnimatedPositioned(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      top: 0,
      bottom: 0,
      left: _isDrawerOpen ? 0 : -MediaQuery.of(context).size.width * 0.75,
      width: MediaQuery.of(context).size.width * 0.75,
      child: FadeTransition(
        opacity: _animationController,
        child: IgnorePointer(
          ignoring: !_isDrawerOpen,
          child: Material(
            color: const Color.fromARGB(255, 234, 232, 232),
            elevation: 8.0,
            child: SafeArea(
              child: Column(
                children: [
                  DrawerHeader(
                    child: SingleChildScrollView(
                      child: Column(
                        spacing: 10,
                        children: [
                          Text('历史对话', style: widget._appConfig.textStyle),
                          TextButton(
                            onPressed: () {
                              setState(() {
                                _historyName = "未命名对话";
                                _history = [];
                                _caches = [];
                                _stepProgressController.setCurrentStep(-1);
                              });
                              _closeDrawer();
                            },
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                            ),
                            child: Text(
                              "新对话",
                              style: widget._appConfig.textStyle,
                            ),
                          ),
                          TextButton(
                            onPressed: () {
                              widget._setPage(
                                PageIndex.setting,
                                serverName: widget._serverName,
                              );
                            },
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.settings, color: Colors.black),
                                const SizedBox(width: 5),
                                Text("设置", style: widget._appConfig.textStyle),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      padding: EdgeInsets.zero,
                      children: _buildDrawerItems(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    // 详情面板
    Widget detail = AnimatedPositioned(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      top: 20,
      bottom: 20,
      right: _showDetail ? 15 : -(MediaQuery.of(context).size.width),
      width: MediaQuery.of(context).size.width - 70,
      child: Stack(
        children: [
          Container(
            height: double.infinity,
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(20),
            ),
            child: Flex(
              direction: Axis.vertical,
              mainAxisAlignment: MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.center,
              spacing: 10,
              children: [
                const SizedBox(height: 30),
                StepProgress(
                  totalSteps: 4,
                  stepNodeSize: 20,
                  nodeTitles: ["RAG检索", "构建提示词", "分词", "推理"],
                  controller: _stepProgressController,
                  theme: const StepProgressThemeData(
                    nodeLabelAlignment: StepLabelAlignment.top,
                    stepLineSpacing: 2,
                    stepLineStyle: StepLineStyle(lineThickness: 2),
                    activeForegroundColor: Colors.lightBlueAccent,
                  ),
                ),
                const SizedBox(height: 20),
                _caches.isEmpty
                    ? const SizedBox.shrink()
                    : Expanded(
                        child: ListView.separated(
                          itemCount: _caches.length,
                          itemBuilder: (BuildContext context, int index) {
                            return TextButton(
                              onPressed: () {
                                showAlertDialog(
                                  context,
                                  _details[index],
                                  title: const Icon(Icons.details),
                                  textStyle: widget._appConfig.textStyle,
                                );
                              },
                              child: Text(
                                _caches[index],
                                style: widget._appConfig.textStyle,
                              ),
                            );
                          },
                          separatorBuilder: (BuildContext context, int index) {
                            return Divider();
                          },
                        ),
                      ),
              ],
            ),
          ),
          Positioned(
            top: 5,
            right: 10,
            child: IconButton(
              onPressed: () {
                setState(() {
                  _showDetail = false;
                });
              },
              icon: const Icon(Icons.close),
            ),
          ),
        ],
      ),
    );

    return Container(
      width: double.infinity,
      height: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Stack(
        children: [
          Flex(
            direction: Axis.vertical,
            children: [
              Container(
                height: 60,
                child: Center(
                  child: Text(_historyName, style: widget._appConfig.textStyle),
                ),
              ),
              Divider(color: Colors.grey[100]),
              const SizedBox(height: 15),
              Expanded(
                child: ListView.separated(
                  itemBuilder: (context, index) => _Bubble(
                    appConfig: widget._appConfig,
                    sender: _history[index]["role"],
                    content: _history[index]["content"],
                  ),
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 30),
                  itemCount: _history.length,
                ),
              ),
              Container(
                height: 60,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () {
                        if (!_recording) {
                          setState(() {
                            _recording = true;
                          });
                        } else {
                          setState(() {
                            _recording = false;
                          });

                          // TODO: 语音转文本
                          _sendMessage("一段语音...");
                        }
                      },
                      icon: Icon(
                        _recording ? Icons.stop : Icons.mic,
                        color: _recording ? Colors.red : Colors.black,
                      ),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: TextField(
                        enabled: !_recording,
                        controller: _messageController,
                        decoration: InputDecoration(
                          hintText: "请输入",
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 20),
                    IconButton(
                      onPressed: () {
                        if (_messageController.text.isNotEmpty) {
                          _sendMessage(_messageController.text);
                          _messageController.clear();
                        } else {
                          showAlertDialog(
                            context,
                            "输入不能为空!",
                            textStyle: widget._appConfig.textStyle,
                          );
                        }
                      },
                      icon: const Icon(Icons.send, size: 25),
                    ),
                  ],
                ),
              ),
            ],
          ),
          Positioned(
            top: 10,
            right: 0,
            child: IconButton(
              onPressed: () {
                if (_stepProgressController.currentStep != -1) {
                  setState(() {
                    _showDetail = true;
                  });
                }
              },
              icon: const Icon(Icons.list, size: 30),
            ),
          ),
          Positioned(
            top: 10,
            left: 0,
            child: IconButton(
              onPressed: _toggleDrawer,
              icon: const Icon(Icons.history, size: 30),
            ),
          ),
          overlay,
          drawer,
          detail,
        ],
      ),
    );
  }

  Future<void> _startProgress() async {
    await Future.delayed(Duration(seconds: 1));
    _stepProgressController.nextStep();
    await Future.delayed(Duration(seconds: 1));
    _stepProgressController.nextStep();
    await Future.delayed(Duration(seconds: 1));
    _stepProgressController.nextStep();
    await Future.delayed(Duration(seconds: 1));
    _stepProgressController.nextStep();

    setState(() {
      _caches.add("总则");
      _caches.add("网络安全支持与促进");
      _details.add(
        """第一条　为了保障网络安全，维护网络空间主权和国家安全、社会公共利益，保护公民、法人和其他组织的合法权益，促进经济社会信息化健康发展，制定本法。

      第二条　在中华人民共和国境内建设、运营、维护和使用网络，以及网络安全的监督管理，适用本法。

      第三条　网络安全工作坚持中国共产党的领导，贯彻总体国家安全观，统筹发展和安全，推进网络强国建设。

      第四条　国家坚持网络安全与信息化发展并重，遵循积极利用、科学发展、依法管理、确保安全的方针，推进网络基础设施建设和互联互通，鼓励网络技术创新和应用，支持培养网络安全人才，建立健全网络安全保障体系，提高网络安全保护能力。

      第五条　国家制定并不断完善网络安全战略，明确保障网络安全的基本要求和主要目标，提出重点领域的网络安全政策、工作任务和措施。

      第六条　国家采取措施，监测、防御、处置来源于中华人民共和国境内外的网络安全风险和威胁，保护关键信息基础设施免受攻击、侵入、干扰和破坏，依法惩治网络违法犯罪活动，维护网络空间安全和秩序。

      第七条　国家倡导诚实守信、健康文明的网络行为，推动传播社会主义核心价值观，采取措施提高全社会的网络安全意识和水平，形成全社会共同参与促进网络安全的良好环境。

      第八条　国家积极开展网络空间治理、网络技术研发和标准制定、打击网络违法犯罪等方面的国际交流与合作，推动构建和平、安全、开放、合作的网络空间，建立多边、民主、透明的网络治理体系。

      第九条　国家网信部门负责统筹协调网络安全工作和相关监督管理工作。国务院电信主管部门、公安部门和其他有关机关依照本法和有关法律、行政法规的规定，在各自职责范围内负责网络安全保护和监督管理工作。

      县级以上地方人民政府有关部门的网络安全保护和监督管理职责，按照国家有关规定确定。

      第十条　网络运营者开展经营和服务活动，必须遵守法律、行政法规，尊重社会公德，遵守商业道德，诚实信用，履行网络安全保护义务，接受政府和社会的监督，承担社会责任。

      第十一条　建设、运营网络或者通过网络提供服务，应当依照法律、行政法规的规定和国家标准的强制性要求，采取技术措施和其他必要措施，保障网络安全、稳定运行，有效应对网络安全事件，防范网络违法犯罪活动，维护网络数据的完整性、保密性和可用性。

      第十二条　网络相关行业组织按照章程，加强行业自律，制定网络安全行为规范，指导会员加强网络安全保护，提高网络安全保护水平，促进行业健康发展。

      第十三条　国家保护公民、法人和其他组织依法使用网络的权利，促进网络接入普及，提升网络服务水平，为社会提供安全、便利的网络服务，保障网络信息依法有序自由流动。

      任何个人和组织使用网络应当遵守宪法法律，遵守公共秩序，尊重社会公德，不得危害网络安全，不得利用网络从事危害国家安全、荣誉和利益，煽动颠覆国家政权、推翻社会主义制度，煽动分裂国家、破坏国家统一，宣扬恐怖主义、极端主义，宣扬民族仇恨、民族歧视，传播暴力、淫秽色情信息，编造、传播虚假信息扰乱经济秩序和社会秩序，以及侵害他人名誉、隐私、知识产权和其他合法权益等活动。

      第十四条　国家支持研究开发有利于未成年人健康成长的网络产品和服务，依法惩治利用网络从事危害未成年人身心健康的活动，为未成年人提供安全、健康的网络环境。

      第十五条　任何个人和组织有权对危害网络安全的行为向网信、电信、公安等部门举报。收到举报的部门应当及时依法作出处理；不属于本部门职责的，应当及时移送有权处理的部门。

      有关部门应当对举报人的相关信息予以保密，保护举报人的合法权益。
""",
      );
      _details.add(
        """第十六条　国家建立和完善网络安全标准体系。国务院标准化行政主管部门和国务院其他有关部门根据各自的职责，组织制定并适时修订有关网络安全管理以及网络产品、服务和运行安全的国家标准、行业标准。

      国家支持企业、研究机构、高等学校、网络相关行业组织参与网络安全国家标准、行业标准的制定。

      第十七条　国务院和省、自治区、直辖市人民政府应当统筹规划，加大投入，扶持重点网络安全技术产业和项目，支持网络安全技术的研究开发和应用，推广安全可信的网络产品和服务，保护网络技术知识产权，支持企业、研究机构和高等学校等参与国家网络安全技术创新项目。

      第十八条　国家推进网络安全社会化服务体系建设，鼓励有关企业、机构开展网络安全认证、检测和风险评估等安全服务。

      第十九条　国家鼓励开发网络数据安全保护和利用技术，促进公共数据资源开放，推动技术创新和经济社会发展。

      第二十条　国家支持人工智能基础理论研究和算法等关键技术研发，推进训练数据资源、算力等基础设施建设，完善人工智能伦理规范，加强风险监测评估和安全监管，促进人工智能应用和健康发展。

      国家支持创新网络安全管理方式，运用人工智能等新技术，提升网络安全保护水平。

      第二十一条　各级人民政府及其有关部门应当组织开展经常性的网络安全宣传教育，并指导、督促有关单位做好网络安全宣传教育工作。

      大众传播媒介应当有针对性地面向社会进行网络安全宣传教育。

      第二十二条　国家支持企业和高等学校、职业学校等教育培训机构开展网络安全相关教育与培训，采取多种方式培养网络安全人才，促进网络安全人才交流。
""",
      );
    });

    widget._addCache(LawCache(_historyName, _caches, _details));
  }
}

class _Bubble extends StatelessWidget {
  final String _sender;
  final String _content;
  final AppConfig _appConfig;

  const _Bubble({
    Key? key,
    required this._sender,
    required this._content,
    required this._appConfig,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: (_sender == "user")
          ? Alignment.centerRight
          : Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: (_sender == "user")
            ? [
                ChatBubble(
                  backGroundColor: const Color(0xFF2B6BFF), // DeepSeek 品牌蓝
                  clipper: ChatBubbleClipper10(type: BubbleType.sendBubble),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.6,
                    ),
                    child: Text(
                      _content,
                      style: TextStyle(
                        color: const Color(0xFFFFFFFF),
                        fontSize: _appConfig.textStyle.fontSize,
                      ),
                    ),
                  ),
                ),
              ]
            : [
                ChatBubble(
                  backGroundColor: Colors.grey[300],
                  clipper: ChatBubbleClipper10(type: BubbleType.receiverBubble),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.55,
                    ),
                    child: Text(_content, style: _appConfig.textStyle),
                  ),
                ),
              ],
      ),
    );
  }
}
